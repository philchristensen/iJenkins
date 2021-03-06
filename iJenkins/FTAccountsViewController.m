//
//  FTAccountsViewController.m
//  iJenkins
//
//  Created by Ondrej Rafaj on 29/08/2013.
//  Copyright (c) 2013 Fuerte Innovations. All rights reserved.
//

#import "FTAccountsViewController.h"
#import "FTServerHomeViewController.h"
#import "FTNoAccountCell.h"
#import "FTAccountCell.h"
#import "FTIconCell.h"
#import "FTSmallTextCell.h"
#import "GCNetworkReachability.h"
#import "BonjourBuddy.h"
#import "NSData+Networking.h"


@interface FTAccountsViewController () <FTAccountCellDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *data;
@property (nonatomic, strong) NSArray *demoAccounts;

@property (nonatomic, strong) NSMutableDictionary *reachabilityCache;
@property (nonatomic, strong) NSMutableDictionary *reachabilityStatusCache;

@property (nonatomic, strong) BonjourBuddy *bonjour;
@property (nonatomic, strong) NSArray *bonjourAccounts;

@end


@implementation FTAccountsViewController


#pragma mark Initialization

- (id)init {
    self = [super init];
    if (self) {
        _reachabilityStatusCache = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark Layout

- (void)scrollToAccount:(FTAccount *)account {
    
}

#pragma mark Data

- (void)reloadData {
    [super.tableView reloadData];
}

- (NSArray *)datasourceForIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return _data;
            break;
            
        case 1:
            return _bonjourAccounts;
            break;
            
        case 2:
            return _demoAccounts;
            break;
            
        default:
            return nil;
            break;
    }
}

- (FTAccount *)accountForIndexPath:(NSIndexPath *)indexPath {
    return [[self datasourceForIndexPath:indexPath] objectAtIndex:indexPath.row];
}

#pragma mark Creating elements

- (void)createTableView {
    _data = [[FTAccountsManager sharedManager] accounts];
    _demoAccounts = [[FTAccountsManager sharedManager] demoAccounts];
    
    [super createTableView];
}

- (void)createTopButtons {
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(didCLickAddItem:)];
    [self.navigationItem setLeftBarButtonItem:add];
    
    UIBarButtonItem *edit = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(didCLickEditItem:)];
    [self.navigationItem setRightBarButtonItem:edit];
}

- (void)createAllElements {
    [super createAllElements];
    
    [self createTableView];
    [self createTopButtons];
    
    [self setTitle:FTLangGet(@"Servers")];
    
    [self startCheckingForJenkins];
}

#pragma mark View lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [FTAPIConnector stopLoadingAll];
    
    //  Custom UIMenuController items for the accounts
    //  These are added only for this controller and are removed at the -viewWillDisappear
    UIMenuItem *copyUrlItem = [[UIMenuItem alloc] initWithTitle:FTLangGet(@"Copy URL") action:@selector(copyURL:)];
    UIMenuItem *openInBrowser = [[UIMenuItem alloc] initWithTitle:FTLangGet(@"Open in browser") action:@selector(openInBrowser:)];
    [[UIMenuController sharedMenuController] setMenuItems: @[copyUrlItem, openInBrowser]];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    //  Remove custom menu actions
    [[UIMenuController sharedMenuController] setMenuItems:nil];
}

#pragma mark Actions

- (void)didCLickAddItem:(UIBarButtonItem *)sender {
    FTAddAccountViewController *c = [[FTAddAccountViewController alloc] init];
    [c setIsNew:YES];
    FTAccount *acc = [[FTAccount alloc] init];
    [c setAccount:acc];
    [c setDelegate:self];
    [c setTitle:FTLangGet(@"New Instance")];
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:c];
    [self presentViewController:nc animated:YES completion:^{
        
    }];
}

- (void)didCLickEditItem:(UIBarButtonItem *)sender {
    [super.tableView setEditing:!super.tableView.editing animated:YES];
    
    UIBarButtonSystemItem item;
    if (self.tableView.editing) {
        item = UIBarButtonSystemItemDone;
    }
    else {
        item = UIBarButtonSystemItemEdit;
    }
    UIBarButtonItem *edit = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:item target:self action:@selector(didCLickEditItem:)];
    [self.navigationItem setRightBarButtonItem:edit animated:YES];
}

#pragma mark Bonjour Jenkins discovery

- (void)startCheckingForJenkins {
    _bonjour = [[BonjourBuddy alloc] initWithServiceId:@"_hudson._tcp."];
    _bonjour.me = @{@"name": [[UIDevice currentDevice] name]};
    [_bonjour start];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(peersChanged) name:BonjourBuddyPeersChangedNotification object:nil];
}

#pragma mark Bonjour discovery

- (BOOL)isAccountUrlInBonjour:(NSURL *)url {
    for (FTAccount *acc in _bonjourAccounts) {
        if ([acc.host isEqualToString:url.host] && acc.port == url.port.integerValue) {
            return YES;
        }
    }
    return NO;
}

- (void)peersChanged {
    if (self == self.navigationController.viewControllers.lastObject) {
        NSMutableArray *arr = [NSMutableArray array];
        for (NSDictionary *peer in _bonjour.peers) {
            NSURL *url = [NSURL URLWithString:peer[@"url"]];
            if (peer[@"url"]) {
                FTAccount *acc = [[FTAccount alloc] init];
                [acc setAccountType:FTAccountTypeBonjour];
                NSNetService *service = peer[@"service"];
                if (service.addresses.count > 0) {
                    NSMutableArray *addr = [NSMutableArray array];
                    for (NSData *data in service.addresses) {
                        NSString *host = [data host];
                        if (acc.host.length < 2) [acc setHost:[host copy]];
                        [addr addObject:host];
                    }
                    [acc setAlternativeAddresses:[addr copy]];
                }
                else {
                    [acc setHost:url.host];
                }
                [acc setHost:url.host];
                [acc setName:url.host];
                [acc setPort:service.port];
                [acc setHttps:[url.scheme isEqualToString:@"https"]];
                [arr addObject:acc];
                
                if (acc.alternativeAddresses.count > 0) {
                    FTAccount *acc2 = [[FTAccount alloc] init];
                    NSString *host = acc.alternativeAddresses.lastObject;
                    [acc2 setHost:host];
                    [acc2 setName:[NSString stringWithFormat:@"%@ (%@)", acc.name, FTLangGet(@"Alternative")]];
                    [acc2 setPort:acc.port];
                    [acc2 setHttps:acc.https];
                    [acc2 setAlternativeAddresses:acc.alternativeAddresses];
                    [arr addObject:acc2];
                }
            }
        }
        _bonjourAccounts = [arr copy];
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark Table view delegate and data source methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return ((_data.count > 0) ? _data.count : 1);
            break;
            
        case 1:
            return ((_bonjourAccounts.count > 0) ? _bonjourAccounts.count : 1);
            break;
            
        case 2:
            return _demoAccounts.count;
            break;
            
        case 3:
            return 1;
            break;
            
        default:
            return 0;
            break;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && _data.count == 0) {
        return 100;
    }
    else {
        return 54;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return FTLangGet(@"Your accounts");
            break;
            
        case 1:
            return FTLangGet(@"Local network");
            break;
            
        case 2:
            return FTLangGet(@"Demo account");
            break;
            
        case 3:
            return FTLangGet(@"About");
            break;
            
        default:
            return nil;
            break;
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((indexPath.section == 0 && _data.count == 0) || indexPath.section) {
        return NO;
    }
    else return (indexPath.section == 0);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        FTAccount *acc = [_data objectAtIndex:indexPath.row];
        [[FTAccountsManager sharedManager] removeAccount:acc];
        [tableView reloadData];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.section == 0 && [_data count] > 1);
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    FTAccount *movedAccount = [self accountForIndexPath:sourceIndexPath];
    [[FTAccountsManager sharedManager] moveAccount:movedAccount toIndex:destinationIndexPath.row];
}

- (UITableViewCell *)cellForNoAccount {
    static NSString *identifier = @"noAccountCell";
    FTNoAccountCell *cell = [super.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[FTNoAccountCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    return cell;
}

- (UITableViewCell *)accountCellForIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"accountCell";
    FTAccountCell *cell = [super.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[FTAccountCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.delegate = self;
        
    }
    if (indexPath.section == 0) {
        [cell setAccessoryType:UITableViewCellAccessoryDetailDisclosureButton];
    }
    else {
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    }
    __block FTAccount *acc = [self accountForIndexPath:indexPath];
    [cell.textLabel setText:acc.name];
    NSString *port = (acc.port != 0) ? [NSString stringWithFormat:@":%d", acc.port] : @"";
    [cell.detailTextLabel setText:[NSString stringWithFormat:@"%@%@", acc.host, port]];
    
    //  Status of the server
    NSNumber *key = @([acc hash]);
    NSNumber *statusNumber = _reachabilityStatusCache[key];
    
    if (indexPath.section == 1) {
        statusNumber = [NSNumber numberWithInt:FTAccountCellReachabilityStatusReachable];
    }
    else {
        if (acc.host.length > 0) {
            GCNetworkReachability *r = _reachabilityCache[acc.host];
            if (!r) {
                r = [GCNetworkReachability reachabilityWithHostName:acc.host];
                if (!_reachabilityCache) {
                    _reachabilityCache = [NSMutableDictionary dictionary];
                }
                _reachabilityCache[acc.host] = r;
                [r startMonitoringNetworkReachabilityWithHandler:^(GCNetworkReachabilityStatus status) {
                    __block FTAccountCellReachabilityStatus s = (status == GCNetworkReachabilityStatusNotReachable) ? FTAccountCellReachabilityStatusUnreachable : FTAccountCellReachabilityStatusReachable;
                    if (status == GCNetworkReachabilityStatusNotReachable) {
                        _reachabilityStatusCache[key] = @(s);
                        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                    }
                    else {
                        _reachabilityStatusCache[key] = @(s);
                        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                        
                        // TODO: Finish the API request to check server API, not just reachability
                        /*
                         [[FTAccountsManager sharedManager] setSelectedAccount:acc];
                         FTAPIOverallLoadDataObject *loadObject = [[FTAPIOverallLoadDataObject alloc] init];
                         [FTAPIConnector connectWithObject:loadObject andOnCompleteBlock:^(id<FTAPIDataAbstractObject> dataObject, NSError *error) {
                         if (error) {
                         s = FTAccountCellReachabilityStatusUnreachable;
                         }
                         else {
                         s = FTAccountCellReachabilityStatusReachable;
                         }
                         _reachabilityStatusCache[key] = @(s);
                         [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                         }];
                         */
                    }
                }];
            }
        }
    }
    
    if (statusNumber) {
        cell.reachabilityStatus = [statusNumber unsignedIntegerValue];
    }
    else {
        cell.reachabilityStatus = FTAccountCellReachabilityStatusLoading;
        _reachabilityStatusCache[key] = @(FTAccountCellReachabilityStatusLoading);
    }
    
    return cell;
}

- (FTBasicCell *)cellForAboutSection:(NSIndexPath *)indexPAth {
    static NSString *identifier = @"aboutSectionCell";
    FTIconCell *cell = [super.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[FTIconCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    }
    [cell.iconView setDefaultIconIdentifier:@"icon-github"];
    [cell.textLabel setText:FTLangGet(@"Open source project")];
    [cell.detailTextLabel setText:FTLangGet(@"All source code available on github.com")];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && _data.count == 0) {
        return [self cellForNoAccount];
    }
    else if (indexPath.section == 1) {
        if (_bonjourAccounts.count > 0) {
            return [self accountCellForIndexPath:indexPath];
        }
        else {
            return [FTSmallTextCell smallTextCellForTable:tableView withText:FTLangGet(@"No instances available at the moment")];
        }
    }
    else {
        if (indexPath.section == 0 || indexPath.section == 2) {
            return [self accountCellForIndexPath:indexPath];
        }
        else {
            return [self cellForAboutSection:indexPath];
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && _data.count == 0) {
        [self didCLickAddItem:nil];
    }
    else {
        if (indexPath.section != 3) {
            if ([self datasourceForIndexPath:indexPath].count > 0) {
                FTAccount *acc = [self accountForIndexPath:indexPath];
                [[FTAccountsManager sharedManager] setSelectedAccount:acc];
                [FTAPIConnector resetForAccount:acc];
                
                FTServerHomeViewController *c = [[FTServerHomeViewController alloc] init];
                [c setTitle:acc.name];
                [self.navigationController pushViewController:c animated:YES];
            }
        }
        else {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/rafiki270/iJenkins"]];
        }
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    FTAccount *acc = [self accountForIndexPath:indexPath];
    FTAddAccountViewController *c = [[FTAddAccountViewController alloc] init];
    [c setDelegate:self];
    [c setTitle:acc.name];
    [c setAccount:acc];
    
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:c];
    [self presentViewController:nc animated:YES completion:^{
        
    }];
}

//  Showing menu overlay
- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    return [cell isKindOfClass:[FTAccountCell class]];
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    return [cell canPerformAction:action withSender:sender];
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    //  This method have to be present in order to make the UIMenuController work, however there is no imlementation needed as the functionality is handled using cell delegate
}

#pragma mark Add account view controller delegate methods

- (void)addAccountViewController:(FTAddAccountViewController *)controller didAddAccount:(FTAccount *)account {
    [[FTAccountsManager sharedManager] addAccount:account];
    [self reloadData];
    [self scrollToAccount:account];
    [self dismissViewControllerAnimated:YES completion:^{
        
    }];
}

- (void)addAccountViewController:(FTAddAccountViewController *)controller didModifyAccount:(FTAccount *)account {
    [[FTAccountsManager sharedManager] updateAccount:account];
    [self reloadData];
    [self scrollToAccount:account];
    [self dismissViewControllerAnimated:YES completion:^{
        
    }];
}

- (void)addAccountViewControllerCloseWithoutSave:(FTAddAccountViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:^{
        [controller resetAccountToOriginalStateIfNotNew];
    }];
}

#pragma mark Account cell delegate

- (void)accountCellMenuCopyURLSelected:(FTAccountCell *)cell {
    FTAccount *account = [self accountForCell:cell];
    NSURL *serverURL = [NSURL URLWithString:[account baseUrl]];
    [[UIPasteboard generalPasteboard] setURL:serverURL];
}

- (void)accountCellMenuOpenInBrowserSelected:(FTAccountCell *)cell {
    FTAccount *account = [self accountForCell:cell];
    NSURL *serverURL = [NSURL URLWithString:[account baseUrl]];
    [[UIApplication sharedApplication] openURL:serverURL];
}

#pragma mark Private methods

- (FTAccount *)accountForCell:(FTAccountCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    return [self accountForIndexPath:indexPath];
}

@end
