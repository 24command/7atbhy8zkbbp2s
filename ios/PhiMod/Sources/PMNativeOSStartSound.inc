// Included by PMNativeOSPlayTransition.inc within pmnativeosscene.
// Accepted user Start, NOT an animation/capture callback. Retail 4.0.4 C8
// (0x153895c), C9 phase 1 (0x14f5160) and phase 2 (0x15164c4) invoke
// SEPlayer.Play(6) after their onPlay latch, before any intro/BGM fade.
// Index 6 is Tap7 in both level0 audioClips and nativeAudioClips. Invoke the
// installed delegate so stock backend selection and SE volume stay intact.
// Caller owns the acceptance latch: call once before chapterStartIntro, never
// on resume/commit. Later failure/cancellation does not retract or replay it.
bool playStartSound(Runtime &r){
    if(!NSThread.isMainThread)return false;
    return entrance::checked([&]{
        P callback=r.staticValue<P>(r.klass("SEPlayer"),"Play","SEPlayer.play");
        entrance::require(callback,"Play: SEPlayer.Play is not ready");
        int index=6;
        r.call(callback,"Invoke",{"System.Int32"},{&index});
    });
}
