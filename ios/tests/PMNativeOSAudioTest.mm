// Compile this translation unit ALONE: it includes the real runtime below.
// macOS host: clang++ -DPM_NATIVE_OS_AUDIO_HOST_TEST -fobjc-arc -std=c++17 \
//   PMNativeOSAudioTest.mm -framework Foundation -framework AVFoundation -o audio-test
// iOS target: omit the host define and additionally link UIKit.
// Never also compile/link PMNativeOSAudio.mm. No fake AVAudioPlayer/decoder.
// Only test-local silent PCM WAV fixtures are generated, then deleted.
// No fixture is installed as chapter media; no test requires an audio output device.
#import "../PhiMod/Sources/PMNativeOSAudio.mm"
#include <cassert>
#include <cstdio>
#include <thread>

static PMNativeOSAudio *load(NSArray *cues, NSString *chapter, NSError **error) {
    PMNativeOSAudio *audio = nil;
    NSError *failure = nil;
    std::thread worker([&] { @autoreleasepool {
        audio = [[PMNativeOSAudio alloc] initWithCues:cues chapterDir:chapter error:&failure];
    }});
    worker.join();
    if (error) *error = failure;
    return audio;
}
static NSDictionary *changed(NSDictionary *base, NSString *key, id value) {
    NSMutableDictionary *d = [base mutableCopy]; d[key] = value; return d;
}
// Canonical little-endian stereo PCM16, entirely silent. These tiny fixtures
// exist only under this test's unique temporary chapter directory.
static void writeSilentWav(NSString *path, uint32_t frames) {
    constexpr uint32_t rate = 48000;
    constexpr uint16_t channels = 2, blockAlign = channels * 2;
    const uint32_t payload = frames * blockAlign;
    std::vector<unsigned char> bytes(44 + payload, 0);
    auto le16 = [&](size_t at, uint16_t value) {
        bytes[at] = static_cast<unsigned char>(value);
        bytes[at+1] = static_cast<unsigned char>(value >> 8);
    };
    auto le32 = [&](size_t at, uint32_t value) {
        for (unsigned i=0; i<4; ++i) bytes[at+i] = static_cast<unsigned char>(value >> (8*i));
    };
    std::memcpy(bytes.data(), "RIFF", 4); le32(4, 36 + payload);
    std::memcpy(bytes.data()+8, "WAVEfmt ", 8); le32(16, 16);
    le16(20, 1); le16(22, channels); le32(24, rate);
    le32(28, rate * blockAlign); le16(32, blockAlign); le16(34, 16);
    std::memcpy(bytes.data()+36, "data", 4); le32(40, payload);
    FD file(open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
    assert(file.fd >= 0);
    size_t offset = 0;
    while (offset < bytes.size()) {
        ssize_t n = write(file.fd, bytes.data()+offset, bytes.size()-offset);
        if (n < 0 && errno == EINTR) continue;
        assert(n > 0); offset += static_cast<size_t>(n);
    }
}
static void successfulIntroLoopDecode(NSString *chapter) {
    NSString *introName = @"test-silence-intro.wav", *loopName = @"test-silence-loop.wav";
    NSString *media = [chapter stringByAppendingPathComponent:@"os-media"];
    NSString *introPath = [media stringByAppendingPathComponent:introName];
    NSString *loopPath = [media stringByAppendingPathComponent:loopName];
    writeSilentWav(introPath, 2400); // 50 ms, 2 channels, 48 kHz PCM16.
    writeSilentWav(loopPath, 4800);  // 100 ms; total fixtures < 29 KiB.
    std::thread worker([&] { @autoreleasepool {
        FD directory(openMedia(chapter)); assert(directory.fd >= 0);
        for (NSString *name in @[introName, loopName]) {
            NSError *error = nil;
            NSData *bytes = readAudio(directory.fd, name, FileLimit, &error);
            assert(bytes && !error);
            AVAudioPlayer *decoded = [[AVAudioPlayer alloc] initWithData:bytes error:&error];
            assert(decoded && !error && decoded.numberOfChannels == 2);
            const double expected = [name isEqualToString:introName] ? .05 : .1;
            assert(std::fabs(decoded.duration-expected) <= 1.0/48000);
            assert(!decoded.isPlaying);
            // Deliberately no prepareToPlay/play/playAtTime: headless CI only
            // checks the actual AV decoder and the runtime's worker preparation.
        }
    }});
    worker.join();
    NSDictionary *split = @{@"screen":@1, @"event":@"page", @"channel":@"bgm",
        @"src":loopName, @"introSrc":introName, @"loop":@YES};
    // Program always supplies an NSString, including @"" for ordinary cues.
    NSDictionary *plain = @{@"screen":@2, @"src":loopName, @"introSrc":@""};
    NSError *error = nil;
    PMNativeOSAudio *audio = load(@[split, plain], chapter, &error);
    assert(audio && !error && audio.diagnostics.count == 0);
    assert(!audio.ownsBGM && !audio.lastPlaybackError);
    [audio resetPlayback];
    assert(audio.diagnostics.count == 0 && !audio.ownsBGM);
    [audio stop];
    assert(unlink(introPath.fileSystemRepresentation) == 0);
    assert(unlink(loopPath.fileSystemRepresentation) == 0);
    puts("Real AVAudioPlayer PCM decode passed: stereo 50/100 ms intro+loop, empty introSrc, no playback");
}
int main() { @autoreleasepool {
    NSString *chapter = [NSHomeDirectory() stringByAppendingPathComponent:
        [@"Library/Caches/PMNativeOSAudioTest-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSFileManager *fm = NSFileManager.defaultManager;
    assert([fm createDirectoryAtPath:[chapter stringByAppendingPathComponent:@"os-media"]
        withIntermediateDirectories:YES attributes:nil error:nil]);
    successfulIntroLoopDecode(chapter);
    NSDictionary *base = @{@"screen":@1, @"src":@"missing.m4a"};
    NSError *error = nil;
    assert(![[PMNativeOSAudio alloc] initWithCues:@[base] chapterDir:chapter error:&error] && error);
    PMNativeOSAudio *audio = load(@[base],chapter,&error);
    assert(audio && !error && audio.diagnostics.count == 1);
    assert(!audio.ownsBGM && !audio.lastPlaybackError);
    __block int changes = 0;
    audio.bgmOwnershipChanged = ^(BOOL) { ++changes; };
    [audio tickAt:50 active:YES]; [audio tap:1 node:nil time:50];
    [audio activateScreen:1 time:0]; [audio tickAt:1 active:YES];
#if defined(PM_NATIVE_OS_AUDIO_HOST_TEST)
    injectHostApplicationActive(NO);
    assert(applicationInactive());
    [audio tickAt:1 active:YES];
    injectHostApplicationActive(YES);
    assert(!applicationInactive());
#endif
    [audio setSuspended:YES]; [audio setSuspended:NO];
    [audio resetPlayback]; [audio activateScreen:1 time:0];
    assert(audio.diagnostics.count == 1);
    [audio stop]; [audio stop]; [audio resetPlayback]; [audio activateScreen:1 time:0];
    assert(!audio.ownsBGM && changes == 0);

    for (NSString *src in @[@"../a.wav", @"/a.wav", @"a\\b.wav", @"a:b.wav", @".a.wav", @"a.ogg", @"https://a.wav"])
        assert(!load(@[changed(base,@"src",src)],chapter,&error) && error);
    for (id screen in @[@YES,@(-1),@(0.5),@(NAN),@"1"])
        assert(!load(@[changed(base,@"screen",screen)],chapter,&error) && error);
    for (id volume in @[@YES,@(-0.1),@(1.1),@(INFINITY),@"1"])
        assert(!load(@[changed(base,@"volume",volume)],chapter,&error) && error);
    assert(!load(@[base,base],chapter,&error) && error);
    NSMutableArray *tooMany = [NSMutableArray array];
    for (int i=0;i<65;++i) [tooMany addObject:changed(base,@"screen",@(i))];
    assert(!load(tooMany,chapter,&error) && error);
    NSDictionary *split = changed(changed(base,@"loop",@YES),@"introSrc",@"missing-intro.m4a");
    audio = load(@[split],chapter,&error);
    assert(audio && !error && audio.diagnostics.count == 2); [audio stop];
    assert(!load(@[changed(base,@"introSrc",@"intro.m4a")],chapter,&error) && error);
    assert(!load(@[changed(split,@"introSrc",@"missing.m4a")],chapter,&error) && error);
    assert(!load(@[changed(split,@"introSrc",@"../intro.m4a")],chapter,&error) && error);
    assert(!load(@[changed(split,@"event",@"tap")],chapter,&error) && error);
    NSDictionary *tap = changed(base,@"event",@"tap");
    assert(!load(@[changed(tap,@"start",@1)],chapter,&error) && error);
    assert(!load(@[changed(tap,@"loop",@YES)],chapter,&error) && error);
    assert(!load(@[tap,tap],chapter,&error) && error);
    audio = load(@[tap,changed(tap,@"target",@"node")],chapter,&error);
    assert(audio && !error && audio.diagnostics.count == 1); [audio stop];
    audio = load(@[],chapter,&error); assert(audio && !error && !audio.diagnostics.count); [audio stop];

    // Validate lexical traversal and every descriptor component independently.
    FD valid(openMedia(chapter)); assert(valid.fd >= 0);
    assert(openMedia([chapter stringByAppendingString:@"/../anything"]) < 0);
    assert(openMedia(@"/tmp/untrusted") < 0);
    NSString *link = [chapter stringByAppendingString:@"-link"];
    assert(symlink(chapter.fileSystemRepresentation,link.fileSystemRepresentation) == 0);
    assert(openMedia(link) < 0);
    // A basename that is a directory must never reach AVAudioPlayer.
    NSString *fake = [chapter stringByAppendingPathComponent:@"os-media/directory.wav"];
    assert([fm createDirectoryAtPath:fake withIntermediateDirectories:NO attributes:nil error:nil]);
    audio = load(@[changed(base,@"src",@"directory.wav")],chapter,&error);
    assert(audio && !error && audio.diagnostics.count == 1); [audio stop];
    NSString *fileLink = [chapter stringByAppendingPathComponent:@"os-media/link.wav"];
    assert(symlink(fake.fileSystemRepresentation,fileLink.fileSystemRepresentation) == 0);
    audio = load(@[changed(base,@"src",@"link.wav")],chapter,&error);
    assert(audio && !error && audio.diagnostics.count == 1); [audio stop];
    NSString *fifo = [chapter stringByAppendingPathComponent:@"os-media/pipe.wav"];
    assert(mkfifo(fifo.fileSystemRepresentation,0600) == 0);
    audio = load(@[changed(base,@"src",@"pipe.wav")],chapter,&error);
    assert(audio && !error && audio.diagnostics.count == 1); [audio stop];
    assert(unlink(link.fileSystemRepresentation) == 0);
    assert([fm removeItemAtPath:chapter error:nil]);
    puts("PMNativeOSAudio: real decoder preparation, schema, missing-resource isolation and safe-path tests passed");
} return 0; }
