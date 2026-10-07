#import "JeevesJellyfinDetailViewController.h"
#import "JeevesJellyfinItem.h"
#import "JeevesJellyfinClient.h"
#import "JeevesJellyfinNowPlayingViewController.h"
#import "UIViewController+JeevesRefresh.h"
#import "JeevesThemeManager.h"

@interface JeevesJellyfinDetailViewController ()
@property (nonatomic, strong) JeevesJellyfinItem *item;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *artView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *resumeButton;
@end

@implementation JeevesJellyfinDetailViewController

- (instancetype)initWithItem:(JeevesJellyfinItem *)item {
    self = [super init];
    if (self) {
        _item = item;
        self.title = item.displayTitle;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    JeevesThemeManager *theme = [JeevesThemeManager sharedManager];
    self.view.backgroundColor = [theme backgroundColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.artView = [[UIImageView alloc] init];
    self.artView.translatesAutoresizingMaskIntoConstraints = NO;
    self.artView.contentMode = UIViewContentModeScaleAspectFill;
    self.artView.clipsToBounds = YES;
    self.artView.backgroundColor = [theme cardBackgroundColor];
    [self.scrollView addSubview:self.artView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.titleLabel.textColor = [theme textColor];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.text = self.item.displayTitle;
    [self.scrollView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [UIFont systemFontOfSize:14];
    self.subtitleLabel.textColor = [theme secondaryTextColor];
    self.subtitleLabel.text = self.item.displaySubtitle;
    [self.scrollView addSubview:self.subtitleLabel];

    self.playButton = [self makeButtonWithTitle:@"Play" color:[theme accentColor]];
    [self.playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.playButton];

    self.resumeButton = [self makeButtonWithTitle:@"Resume" color:[theme cardBackgroundColor]];
    [self.resumeButton addTarget:self action:@selector(resumeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.resumeButton setTitleColor:[theme textColor] forState:UIControlStateNormal];
    self.resumeButton.hidden = (self.item.viewOffsetMs <= 0);
    [self.scrollView addSubview:self.resumeButton];

    self.summaryLabel = [[UILabel alloc] init];
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.font = [UIFont systemFontOfSize:14];
    self.summaryLabel.textColor = [theme textColor];
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.text = self.item.summary;
    [self.scrollView addSubview:self.summaryLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.artView.topAnchor      constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.artView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.artView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.artView.heightAnchor   constraintEqualToConstant:240],

        [self.titleLabel.topAnchor      constraintEqualToAnchor:self.artView.bottomAnchor constant:16],
        [self.titleLabel.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.subtitleLabel.topAnchor      constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.subtitleLabel.leadingAnchor  constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.playButton.topAnchor      constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:16],
        [self.playButton.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.playButton.widthAnchor    constraintEqualToConstant:140],
        [self.playButton.heightAnchor   constraintEqualToConstant:44],

        [self.resumeButton.topAnchor      constraintEqualToAnchor:self.playButton.topAnchor],
        [self.resumeButton.leadingAnchor  constraintEqualToAnchor:self.playButton.trailingAnchor constant:12],
        [self.resumeButton.widthAnchor    constraintEqualToConstant:140],
        [self.resumeButton.heightAnchor   constraintEqualToConstant:44],

        [self.summaryLabel.topAnchor      constraintEqualToAnchor:self.playButton.bottomAnchor constant:16],
        [self.summaryLabel.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.summaryLabel.bottomAnchor   constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-24],
        [self.summaryLabel.widthAnchor    constraintEqualToAnchor:self.view.widthAnchor constant:-32],
    ]];

    [self jeeves_installPullToRefreshOnScrollView:self.scrollView];
    [self jeeves_installWakeRefreshObserver];

    NSString *thumbKey = self.item.art ?: self.item.preferredThumbKey;
    if (thumbKey.length > 0) {
        [[JeevesJellyfinClient sharedClient] loadImageForThumbKey:thumbKey size:CGSizeMake(self.view.bounds.size.width, 240) completion:^(UIImage *img, NSError *e) {
            self.artView.image = img;
        }];
    }
}

- (UIButton *)makeButtonWithTitle:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.layer.cornerRadius = 8;
    return b;
}

- (void)dealloc {
    [self jeeves_removeWakeRefreshObserver];
    [self jeeves_stopRefreshTimer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self jeeves_startRefreshTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self jeeves_stopRefreshTimer];
}

#pragma mark - JeevesRefreshable

- (NSTimeInterval)refreshPollingInterval { return 5.0; }

- (void)refreshFromSource:(JeevesRefreshSource)source {
    [[JeevesJellyfinClient sharedClient] fetchItemWithId:self.item.itemId completion:^(JeevesJellyfinItem *item, NSError *error) {
        [self jeeves_endRefreshing];
        if (item) {
            self.item = item;
            self.titleLabel.text    = item.displayTitle;
            self.subtitleLabel.text = item.displaySubtitle;
            self.summaryLabel.text  = item.summary;
            self.resumeButton.hidden = (item.viewOffsetMs <= 0);
        }
    }];
}

#pragma mark - Actions

- (void)playTapped {
    [self playFromOffset:0];
}

- (void)resumeTapped {
    [self playFromOffset:self.item.viewOffsetMs];
}

- (void)playFromOffset:(NSInteger)offsetMs {
    [[JeevesJellyfinClient sharedClient] playMediaItem:self.item offset:offsetMs completion:^(BOOL ok, id r, NSError *err) {
        if (ok) {
            [self openNowPlaying];
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't Start Playback"
                                                                       message:err.localizedDescription ?: @"The playback target did not respond."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

- (void)openNowPlaying {
    JeevesJellyfinNowPlayingViewController *vc = [[JeevesJellyfinNowPlayingViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
