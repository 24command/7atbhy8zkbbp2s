#import "PMExtensionTracks.h"
#include "../Core/PMRPECore.hpp"
#include <algorithm>
#include <cmath>
#import <dispatch/dispatch.h>
#include <iomanip>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
NSError *extensionError(NSString *message) {
    return [NSError errorWithDomain:@"PhiMod.Extensions" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Invalid RPE extension"}];
}

NSArray *arrayOrEmpty(id value) {
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

double finiteNumber(id value, const char *field) {
    if (![value isKindOfClass:NSNumber.class])
        throw std::runtime_error(std::string("Missing or nonnumeric RPE field: ") + field);
    double result = [value doubleValue];
    if (!std::isfinite(result))
        throw std::runtime_error(std::string("Non-finite RPE field: ") + field);
    return result;
}

double beat(id value) {
    if ([value isKindOfClass:NSNumber.class])
        return finiteNumber(value, "time");
    if (![value isKindOfClass:NSArray.class])
        throw std::runtime_error("Invalid RPE beat tuple");
    NSArray *parts = value;
    if (parts.count != 3)
        throw std::runtime_error("Invalid RPE beat tuple");
    double whole = finiteNumber(parts[0], "time.whole");
    double numerator = finiteNumber(parts[1], "time.numerator");
    double denominator = finiteNumber(parts[2], "time.denominator");
    if (denominator <= 0)
        throw std::runtime_error("Invalid RPE beat denominator");
    return whole + numerator / denominator;
}

struct Tempo {
    std::vector<double> beats, seconds, bpm;

    double at(double value) const {
        if (beats.empty())
            throw std::runtime_error("RPE extra.json has no BPM");
        size_t index = 0;
        while (index + 1 < beats.size() && beats[index + 1] <= value)
            ++index;
        return seconds[index] + (value - beats[index]) * 60.0 / bpm[index];
    }
};

Tempo readTempo(NSDictionary *extra) {
    NSMutableArray *rows = [NSMutableArray new];
    id raw = extra[@"bpm"];
    if ([raw isKindOfClass:NSNumber.class]) {
        [rows addObject:@{@"beat": @0, @"bpm": raw}];
    } else if ([raw isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)raw) {
            if (![item isKindOfClass:NSDictionary.class])
                throw std::runtime_error("Invalid RPE BPM entry");
            NSDictionary *row = item;
            id time = row[@"time"] ?: row[@"startTime"];
            [rows addObject:@{@"beat": @(beat(time)), @"bpm": row[@"bpm"] ?: NSNull.null}];
        }
    } else {
        throw std::runtime_error("RPE extra.json has no BPM");
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double x = [a[@"beat"] doubleValue], y = [b[@"beat"] doubleValue];
        return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
    }];

    Tempo result;
    for (NSDictionary *row in rows) {
        double b = finiteNumber(row[@"beat"], "bpm.time");
        double v = finiteNumber(row[@"bpm"], "bpm");
        if (v <= 0)
            throw std::runtime_error("Invalid RPE BPM");
        result.beats.push_back(b);
        result.bpm.push_back(v);
        if (result.seconds.empty())
            result.seconds.push_back(b * 60.0 / v);
        else
            result.seconds.push_back(result.seconds.back() +
                (b - result.beats[result.beats.size() - 2]) * 60.0 /
                result.bpm[result.bpm.size() - 2]);
    }
    return result;
}

int arity(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        (void)finiteNumber(value, "uniform");
        return 1;
    }
    if (![value isKindOfClass:NSArray.class])
        throw std::runtime_error("RPE uniform must be a number, vector, or event array");
    NSArray *items = value;
    if (items.count && [items[0] isKindOfClass:NSDictionary.class]) {
        NSDictionary *first = items[0];
        return arity(first[@"start"]);
    }
    if (items.count != 2 && items.count != 4)
        throw std::runtime_error("RPE vector uniform must have 2 or 4 channels");
    for (id component in items)
        (void)finiteNumber(component, "uniform.component");
    return (int)items.count;
}

double channelValue(id value, int channel, int channels) {
    if (channels == 1)
        return finiteNumber(value, "uniform.value");
    if (![value isKindOfClass:NSArray.class] || [(NSArray *)value count] != channels)
        throw std::runtime_error("RPE animation channel count changed");
    double result = finiteNumber(value[channel], "uniform.component");
    return channels == 4 ? result / 255.0 : result;
}

std::string hex(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length)
        return "-";
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    std::ostringstream out;
    for (NSUInteger i = 0; i < data.length; ++i)
        out << std::hex << std::setw(2) << std::setfill('0') << (unsigned)bytes[i];
    return out.str();
}

std::string numberText(double value) {
    if (!std::isfinite(value))
        throw std::runtime_error("Non-finite RPE extension animation value");
    std::ostringstream out;
    out << std::setprecision(17) << value;
    return out.str();
}

struct ExtensionTrack {
    std::vector<phimod::rpe::Event> events;
    double fallback = 0;

    double value(double time) const {
        auto it = std::upper_bound(events.begin(), events.end(), time,
            [](double t, const phimod::rpe::Event &event) { return t < event.s; });
        return it == events.begin() ? fallback : (it - 1)->value(time);
    }
};

phimod::rpe::Event readEvent(NSDictionary *object, const Tempo &tempo) {
    phimod::rpe::Event event;
    event.s = tempo.at(beat(object[@"startTime"]));
    event.e = tempo.at(beat(object[@"endTime"]));
    // Uniform/video tracks may animate scalar, vec2, or RGBA values. bake()
    // replaces these placeholders with the selected scalar channel.
    event.a = 0;
    event.b = 0;
    event.left = object[@"easingLeft"] ? finiteNumber(object[@"easingLeft"], "easingLeft") : 0;
    event.right = object[@"easingRight"] ? finiteNumber(object[@"easingRight"], "easingRight") : 1;
    event.easing = object[@"easingType"] ? (int)finiteNumber(object[@"easingType"], "easingType") : 1;
    if (event.e < event.s)
        event.e = event.s;
    if ([object[@"bezier"] intValue] != 0) {
        id rawPoints = object[@"bezierPoints"];
        if (![rawPoints isKindOfClass:NSArray.class] || [(NSArray *)rawPoints count] != 4)
            throw std::runtime_error("Invalid RPE bezier points");
        event.bezier = true;
        for (int i = 0; i < 4; ++i)
            event.points[i] = finiteNumber(rawPoints[i], "bezierPoints");
    }
    return event;
}

void writeSegment(std::ostream &out, const char *kind, int index, const std::string &name,
                  int channel, double start, double end, double from, double to,
                  const ExtensionTrack &track, double tolerance, int depth = 0) {
    if (end <= start)
        return;
    double middle = (start + end) * .5;
    double middleValue = track.value(middle);
    double error = std::fabs(middleValue - (from + to) * .5);
    for (double q : {.25, .75}) {
        double actual = track.value(start + (end - start) * q);
        error = std::max(error, std::fabs(actual - (from + (to - from) * q)));
    }
    if (depth < 14 && end - start > .001 && error > tolerance) {
        writeSegment(out, kind, index, name, channel, start, middle, from, middleValue,
                     track, tolerance, depth + 1);
        writeSegment(out, kind, index, name, channel, middle, end, middleValue, to,
                     track, tolerance, depth + 1);
        return;
    }
    out << "K " << kind << " " << index << " " << name << " " << channel << " "
        << numberText(start) << " " << numberText(end) << " "
        << numberText(from) << " " << numberText(to) << "\n";
}

void bake(std::ostream &out, const char *kind, int index, NSString *name, id raw,
          const Tempo &tempo, double bound, double initial) {
    int channels = arity(raw);
    std::string encodedName = hex(name);
    out << "A " << kind << " " << index << " " << encodedName << " " << channels << "\n";
    NSArray *items = [raw isKindOfClass:NSArray.class] ? raw : nil;
    bool animated = items.count > 0 && [items[0] isKindOfClass:NSDictionary.class];
    for (int channel = 0; channel < channels; ++channel) {
        ExtensionTrack track;
        if (animated) {
            for (id item in items) {
                if (![item isKindOfClass:NSDictionary.class])
                    throw std::runtime_error("Invalid RPE animation event");
                NSDictionary *source = item;
                auto event = readEvent(source, tempo);
                event.a = channelValue(source[@"start"], channel, channels);
                event.b = channelValue(source[@"end"], channel, channels);
                track.events.push_back(event);
            }
            std::stable_sort(track.events.begin(), track.events.end(),
                [](const auto &a, const auto &b) { return a.s < b.s; });
            track.fallback = std::isfinite(initial) ? initial : track.events.front().a;
        } else {
            track.fallback = channelValue(raw, channel, channels);
        }

        std::set<double> cuts{0.0, std::max(1.0, bound)};
        for (const auto &event : track.events) {
            if (event.s > 0 && event.s < bound) cuts.insert(event.s);
            if (event.e > 0 && event.e < bound) cuts.insert(event.e);
        }
        auto it = cuts.begin();
        double last = *it++;
        for (; it != cuts.end(); ++it) {
            double next = *it;
            if (next > last) {
                double from = track.value(last + 1e-8);
                double to = track.value(std::max(last, next - 1e-8));
                writeSegment(out, kind, index, encodedName, channel, last, next,
                             from, to, track, .0005);
            }
            last = next;
        }
        double value = track.value(last + 1e-8);
        constexpr double terminal = 1000000.0 / 64.0;
        if (last < terminal)
            out << "K " << kind << " " << index << " " << encodedName << " " << channel << " "
                << numberText(last) << " " << numberText(terminal) << " "
                << numberText(value) << " " << numberText(value) << "\n";
    }
}

BOOL writeConverted(NSString *text, NSString *destination, NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *parent = destination.stringByDeletingLastPathComponent;
    if (![manager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    if (![text writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:error])
        return NO;
    return [@"1\n" writeToFile:[parent stringByAppendingPathComponent:@"effects-version.txt"]
                       atomically:YES encoding:NSUTF8StringEncoding error:error];
}
}

BOOL PMConvertExtraJSON(NSString *source, NSString *destination, NSError **error) {
    try {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:source];
            if (!data) {
                return writeConverted(@"", destination, error);
            }
            NSError *jsonError = nil;
            id raw = [NSJSONSerialization JSONObjectWithData:data
                options:NSJSONReadingMutableContainers error:&jsonError];
            if (![raw isKindOfClass:NSDictionary.class]) {
                if (error) *error = jsonError ?: extensionError(@"extra.json is not an object");
                return NO;
            }

            NSDictionary *extra = raw;
            Tempo tempo = readTempo(extra);
            std::ostringstream out;

            id rawEffects = extra[@"effects"];
            if (rawEffects && rawEffects != NSNull.null && ![rawEffects isKindOfClass:NSArray.class])
                throw std::runtime_error("RPE effects must be an array");
            NSArray *effects = arrayOrEmpty(rawEffects);
            if (effects.count > 512)
                throw std::runtime_error("Too many RPE shader effects");
            for (NSUInteger i = 0; i < effects.count; ++i) {
                if (![effects[i] isKindOfClass:NSDictionary.class])
                    throw std::runtime_error("Invalid RPE shader effect entry");
                NSDictionary *effect = effects[i];
                double start = tempo.at(beat(effect[@"start"]));
                double end = tempo.at(beat(effect[@"end"]));
                if (end < start)
                    throw std::runtime_error("RPE effect time is reversed");
                id rawShader = effect[@"shader"];
                if (![rawShader isKindOfClass:NSString.class] || ![(NSString *)rawShader length])
                    throw std::runtime_error("RPE effect shader is missing");
                NSString *shader = rawShader;
                out << "F " << i << " " << ([effect[@"global"] boolValue] ? 1 : 0) << " "
                    << numberText(start) << " " << numberText(end) << " " << hex(shader) << "\n";

                id range = effect[@"targetRange"];
                if (range && range != NSNull.null) {
                    NSData *rangeData = [NSJSONSerialization dataWithJSONObject:range
                        options:NSJSONWritingFragmentsAllowed error:nil];
                    if (!rangeData) throw std::runtime_error("Invalid RPE targetRange JSON");
                    NSString *rangeText = [[NSString alloc] initWithData:rangeData encoding:NSUTF8StringEncoding];
                    if (!rangeText) throw std::runtime_error("Could not encode RPE targetRange as UTF-8");
                    out << "R " << i << " " << hex(rangeText) << "\n";
                }
                id rawVars = effect[@"vars"];
                if (rawVars && rawVars != NSNull.null && ![rawVars isKindOfClass:NSDictionary.class])
                    throw std::runtime_error("RPE effect vars must be an object");
                NSDictionary *vars = [rawVars isKindOfClass:NSDictionary.class] ? rawVars : @{};
                static NSRegularExpression *uniformName;
                static dispatch_once_t once;
                dispatch_once(&once, ^{
                    uniformName = [NSRegularExpression regularExpressionWithPattern:
                        @"^[A-Za-z_][A-Za-z0-9_]*$" options:0 error:nil];
                });
                for (NSString *name in vars) {
                    if ([uniformName firstMatchInString:name options:0
                        range:NSMakeRange(0, name.length)] == nil)
                        throw std::runtime_error("Invalid RPE shader uniform name");
                    bake(out, "F", (int)i, name, vars[name], tempo, std::max(1.0, end), NAN);
                }
            }

            id rawVideos = extra[@"videos"];
            if (rawVideos && rawVideos != NSNull.null && ![rawVideos isKindOfClass:NSArray.class])
                throw std::runtime_error("RPE videos must be an array");
            NSArray *videos = arrayOrEmpty(rawVideos);
            if (videos.count > 33)
                throw std::runtime_error("Too many RPE videos (maximum 33)");
            for (NSUInteger i = 0; i < videos.count; ++i) {
                if (![videos[i] isKindOfClass:NSDictionary.class])
                    throw std::runtime_error("Invalid RPE video entry");
                NSDictionary *video = videos[i];
                id rawPath = video[@"path"];
                id rawScale = video[@"scale"];
                NSString *scale = [rawScale isKindOfClass:NSString.class] ? rawScale : @"cropCenter";
                if (![rawPath isKindOfClass:NSString.class] || ![(NSString *)rawPath length] ||
                    [(NSString *)rawPath isAbsolutePath] || [(NSString *)rawPath containsString:@"\\"] ||
                    [(NSString *)rawPath containsString:@":"] ||
                    [scale rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound)
                    throw std::runtime_error("Invalid RPE video path or scale");
                for (NSString *component in [(NSString *)rawPath componentsSeparatedByString:@"/"])
                    if (!component.length || [component isEqualToString:@"."] || [component isEqualToString:@".."])
                        throw std::runtime_error("Unsafe RPE video path");
                double start = video[@"time"] ? tempo.at(beat(video[@"time"])) : 0.0;
                out << "V " << i << " " << numberText(start) << " " << scale.UTF8String
                    << " " << hex(rawPath) << "\n";
                bake(out, "V", (int)i, @"alpha", video[@"alpha"] ?: @1, tempo, 3600.0, 1.0);
                bake(out, "V", (int)i, @"dim", video[@"dim"] ?: @0, tempo, 3600.0, 0.0);
            }

            NSString *converted = [NSString stringWithUTF8String:out.str().c_str()];
            if (!converted) {
                if (error) *error = extensionError(@"Could not encode effects.tsv as UTF-8");
                return NO;
            }
            return writeConverted(converted, destination, error);
        } @catch (NSException *exception) {
            if (error) *error = extensionError(exception.reason);
            return NO;
        }
    } catch (const std::exception &exception) {
        if (error) *error = extensionError([NSString stringWithUTF8String:exception.what()]);
        return NO;
    } catch (...) {
        if (error) *error = extensionError(@"Unknown RPE extension conversion error");
        return NO;
    }
}
