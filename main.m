#import <Cocoa/Cocoa.h>
#include <string.h>

static NSString * const kAppName = @"Codex Context Bar";
static NSTimeInterval const kRefreshInterval = 2.0;

@interface ContextSnapshot : NSObject
@property(nonatomic) NSInteger inputTokens;
@property(nonatomic) NSInteger cachedInputTokens;
@property(nonatomic) NSInteger outputTokens;
@property(nonatomic) NSInteger contextWindow;
@property(nonatomic, copy) NSString *model;
@property(nonatomic, copy) NSDate *timestamp;
@property(nonatomic, copy) NSString *sourcePath;
@property(nonatomic) BOOL hasData;
@end

@implementation ContextSnapshot
@end

@interface ContextReader : NSObject
+ (ContextSnapshot *)readSnapshot;
@end

@implementation ContextReader

+ (NSInteger)integerValue:(id)value {
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

+ (NSDate *)dateFromObject:(NSDictionary *)object {
    NSString *raw = object[@"timestamp"];
    if (![raw isKindOfClass:[NSString class]]) return nil;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    return [formatter dateFromString:raw];
}

+ (NSDictionary *)latestTokenInfoInFile:(NSURL *)url latestDate:(NSDate **)latestDate {
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:url.path error:nil];
    unsigned long long fileSize = [attributes fileSize];
    unsigned long long tailSize = MIN(fileSize, 512ULL * 1024ULL);

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:url.path];
    if (!handle) return nil;
    @try {
        [handle seekToFileOffset:fileSize - tailSize];
        NSData *data = [handle readDataOfLength:(NSUInteger)tailSize];
        [handle closeFile];

        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) return nil;

        NSDictionary *bestInfo = nil;
        NSDate *bestDate = nil;
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (line.length == 0) continue;
            NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *event = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
            if (![event isKindOfClass:[NSDictionary class]]) continue;
            if (![event[@"type"] isEqual:@"event_msg"]) continue;

            NSDictionary *payload = event[@"payload"];
            if (![payload isKindOfClass:[NSDictionary class]] ||
                ![payload[@"type"] isEqual:@"token_count"]) continue;

            NSDictionary *info = payload[@"info"];
            NSDictionary *last = info[@"last_token_usage"];
            NSInteger contextWindow = [self integerValue:info[@"model_context_window"]];
            NSInteger inputTokens = [self integerValue:last[@"input_tokens"]];
            if (contextWindow <= 0 || inputTokens <= 0) continue;

            NSDate *date = [self dateFromObject:event] ?: [NSDate distantPast];
            if (!bestDate || [date compare:bestDate] == NSOrderedDescending) {
                bestDate = date;
                bestInfo = @{
                    @"info": info,
                    @"last": last,
                    @"event": event
                };
            }
        }

        if (latestDate) *latestDate = bestDate;
        return bestInfo;
    } @catch (__unused NSException *exception) {
        [handle closeFile];
        return nil;
    }
}

+ (ContextSnapshot *)readSnapshot {
    ContextSnapshot *snapshot = [[ContextSnapshot alloc] init];
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/sessions"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:root]
                                  includingPropertiesForKeys:@[
                                      NSURLIsRegularFileKey,
                                      NSURLContentModificationDateKey
                                  ]
                                                     options:0
                                                errorHandler:^BOOL(NSURL *url, NSError *error) {
        return YES;
    }];

    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        NSNumber *isRegular = nil;
        [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegular.boolValue || ![url.pathExtension isEqual:@"jsonl"]) continue;
        [files addObject:url];
    }

    [files sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *ad = nil;
        NSDate *bd = nil;
        [a getResourceValue:&ad forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&bd forKey:NSURLContentModificationDateKey error:nil];
        return [bd compare:ad];
    }];

    // Recent rollout files are enough to find the newest token event while
    // keeping the two-second menu-bar refresh cheap on large histories.
    NSUInteger limit = MIN(files.count, 80U);
    NSDate *bestDate = nil;
    NSDictionary *best = nil;
    NSURL *bestURL = nil;
    for (NSUInteger index = 0; index < limit; index++) {
        NSDate *fileDate = nil;
        NSDictionary *candidate = [self latestTokenInfoInFile:files[index] latestDate:&fileDate];
        if (!candidate || !fileDate) continue;
        if (!bestDate || [fileDate compare:bestDate] == NSOrderedDescending) {
            bestDate = fileDate;
            best = candidate;
            bestURL = files[index];
        }
    }

    if (!best) return snapshot;

    NSDictionary *info = best[@"info"];
    NSDictionary *last = best[@"last"];
    NSDictionary *event = best[@"event"];
    snapshot.inputTokens = [self integerValue:last[@"input_tokens"]];
    snapshot.cachedInputTokens = [self integerValue:last[@"cached_input_tokens"]];
    snapshot.outputTokens = [self integerValue:last[@"output_tokens"]];
    snapshot.contextWindow = [self integerValue:info[@"model_context_window"]];
    snapshot.model = event[@"payload"][@"model"] ?: @"Codex";
    snapshot.timestamp = bestDate;
    snapshot.sourcePath = bestURL.path;
    snapshot.hasData = snapshot.contextWindow > 0 && snapshot.inputTokens > 0;
    return snapshot;
}

@end

static NSString *FormatTokens(NSInteger value) {
    if (value >= 1000000) return [NSString stringWithFormat:@"%.2fM", value / 1000000.0];
    if (value >= 1000) return [NSString stringWithFormat:@"%.1fk", value / 1000.0];
    return [NSString stringWithFormat:@"%ld", (long)value];
}

static NSString *FormatDate(NSDate *date) {
    if (!date) return @"—";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    return [formatter stringFromDate:date];
}

static NSString *ContextBar(NSInteger percent, NSUInteger width) {
    NSInteger filled = MAX(0, MIN((NSInteger)width, (NSInteger)llround((double)percent * width / 100.0)));
    NSMutableString *bar = [NSMutableString string];
    for (NSUInteger i = 0; i < width; i++) [bar appendString:(i < filled ? @"▰" : @"▱")];
    return bar;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic, strong) ContextSnapshot *snapshot;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMenuItem *summaryItem;
@property(nonatomic, strong) NSMenuItem *detailItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.statusItem.button.toolTip = kAppName;

    self.menu = [[NSMenu alloc] initWithTitle:kAppName];
    self.menu.delegate = self;
    self.summaryItem = [NSMenuItem separatorItem];
    self.detailItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    self.detailItem.enabled = NO;
    [self.menu addItem:self.detailItem];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:@"Refresh Now"
                                                      action:@selector(refreshNow:)
                                               keyEquivalent:@"r"];
    refresh.target = self;
    [self.menu addItem:refresh];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                   action:@selector(quit:)
                                            keyEquivalent:@"q"];
    quit.target = self;
    [self.menu addItem:quit];
    self.statusItem.menu = self.menu;

    [self refreshNow:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:kRefreshInterval
                                                   target:self
                                                 selector:@selector(refreshNow:)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)refreshNow:(__unused id)sender {
    self.snapshot = [ContextReader readSnapshot];
    [self updateUI];
}

- (void)updateUI {
    ContextSnapshot *s = self.snapshot;
    if (!s.hasData) {
        self.statusItem.button.title = @"CTX —";
        self.statusItem.button.toolTip = @"Codex context: waiting for token data";
        self.detailItem.title = @"Codex context: waiting for token data";
        return;
    }

    NSInteger percent = (NSInteger)llround((double)s.inputTokens * 100.0 / s.contextWindow);
    percent = MAX(0, MIN(100, percent));
    NSString *title = [NSString stringWithFormat:@"CTX %@ %ld%%", ContextBar(percent, 5), (long)percent];
    self.statusItem.button.title = title;
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"Codex context: %ld%% (%@ / %@)",
                                      (long)percent, FormatTokens(s.inputTokens), FormatTokens(s.contextWindow)];
    self.detailItem.title = [NSString stringWithFormat:@"Context  %ld%%  (%@ / %@)",
                             (long)percent, FormatTokens(s.inputTokens), FormatTokens(s.contextWindow)];

    while (self.menu.numberOfItems > 1) [self.menu removeItemAtIndex:1];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Model: %@", s.model ?: @"Codex"]
                                                  action:nil keyEquivalent:@""]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Input: %@    Cached: %@",
                                                          FormatTokens(s.inputTokens), FormatTokens(s.cachedInputTokens)]
                                                  action:nil keyEquivalent:@""]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Output: %@", FormatTokens(s.outputTokens)]
                                                  action:nil keyEquivalent:@""]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Window: %@ tokens",
                                                          FormatTokens(s.contextWindow)]
                                                  action:nil keyEquivalent:@""]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Updated: %@", FormatDate(s.timestamp)]
                                                  action:nil keyEquivalent:@""]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Source: %@", s.sourcePath.lastPathComponent]
                                                  action:nil keyEquivalent:@""]];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:@"Refresh Now"
                                                      action:@selector(refreshNow:)
                                               keyEquivalent:@"r"];
    refresh.target = self;
    [self.menu addItem:refresh];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [self.menu addItem:quit];
}

- (void)quit:(__unused id)sender {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--once") == 0) {
            ContextSnapshot *snapshot = [ContextReader readSnapshot];
            if (!snapshot.hasData) {
                printf("Codex context: waiting for token data\n");
                return 0;
            }
            NSInteger percent = (NSInteger)llround(
                (double)snapshot.inputTokens * 100.0 / snapshot.contextWindow);
            percent = MAX(0, MIN(100, percent));
            printf("Codex context: %ld%% (%ld / %ld tokens)\n",
                   (long)percent,
                   (long)snapshot.inputTokens,
                   (long)snapshot.contextWindow);
            printf("Model: %s\n", snapshot.model.UTF8String ?: "Codex");
            printf("Updated: %s\n", FormatDate(snapshot.timestamp).UTF8String);
            printf("Source: %s\n", snapshot.sourcePath.UTF8String ?: "—");
            return 0;
        }

        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
