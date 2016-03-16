
#import "ViewController.h"

@import Appstax;

@interface ViewController ()
@property NSError *lastError;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateLabel];
}

- (IBAction)requireLogin:(id)sender {
    [AXUser requireLogin:^(AXUser *user) {
        [self updateLabel];
    }];
}

- (IBAction)logout:(id)sender {
    [AXUser logout];
    [self updateLabel];
}

- (IBAction)loginWithFacebook:(id)sender {
    [AXUser loginWithProvider:@"facebook" fromViewController:self completion:^(AXUser *user, NSError *error) {
        self.lastError = error;
        [self updateLabel];
    }];
}

- (void)updateLabel {
    AXUser *user = [AXUser currentUser];
    if(self.lastError != nil) {
        self.label.text = [NSString stringWithFormat:@"Error: %@", self.lastError.userInfo[@"errorMessage"]];
    } else if(user == nil) {
        self.label.text = @"Not logged in";
    } else {
        self.label.text = [NSString stringWithFormat:@"Logged in as %@", user.username];
    }
}

@end
