/*
 Copyright 2015 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXKNotificationSettingsViewController.h"

#import "MXKTableViewCellWithButton.h"
#import "MXKPushRuleTableViewCell.h"
#import "MXKPushRuleCreationTableViewCell.h"
#import "MXKTableViewCellWithTextView.h"

#define MXKNOTIFICATIONSETTINGS_SECTION_INTRO_INDEX      0
#define MXKNOTIFICATIONSETTINGS_SECTION_PER_WORD_INDEX   1
#define MXKNOTIFICATIONSETTINGS_SECTION_PER_ROOM_INDEX   2
#define MXKNOTIFICATIONSETTINGS_SECTION_PER_SENDER_INDEX 3
#define MXKNOTIFICATIONSETTINGS_SECTION_OTHERS_INDEX     4
#define MXKNOTIFICATIONSETTINGS_SECTION_DEFAULT_INDEX    5
#define MXKNOTIFICATIONSETTINGS_SECTION_COUNT            6

NSString* const kGlobalNotificationSettingsMainIntroText = @"Notification settings are saved to your user account and are shared between all clients which support them (including desktop notifications).\n\nRules are applied in order; the first rule which matches defines the outcome for the message.\nSo: Per-word notifications are more important than per-room notifications which are more important than per-sender notifications.\nFor multiple rules of the same kind, the first one in the list that matches takes priority.";
NSString* const kGlobalNotificationSettingsMainIntroTextWhenDisabled = @"All notifications are currently disabled for all devices.";

NSString* const kGlobalNotificationSettingsPerWordIntroText = @"Words match case insensitively, and may include a * wildcard. So:\n\"foo\" matches the string foo surrounded by word delimiters (e.g. punctuation and whitespace or start/end of line).\n\"foo*\" matches any such word that begins foo.\n\"*foo*\" matches any such word which includes the 3 letters foo.";

@interface MXKNotificationSettingsViewController ()
{
    /**
     Handle master rule state
     */
    UIButton *ruleMasterButton;
    BOOL      areAllDisabled;
    
    /**
     */
    NSInteger contentRuleCreationIndex;
    NSInteger roomRuleCreationIndex;
    NSInteger senderRuleCreationIndex;
    
    /**
     Predefined rules index
     */
    NSInteger ruleContainsUserNameIndex;
    NSInteger ruleContainsDisplayNameIndex;
    NSInteger ruleOneToOneRoomIndex;
    NSInteger ruleInviteForMeIndex;
    NSInteger ruleMemberEventIndex;
    NSInteger ruleCallIndex;
    NSInteger ruleSuppressBotsNotificationsIndex;
    
    /**
     Notification center observers
     */
    id notificationCenterWillUpdateObserver;
    id notificationCenterDidUpdateObserver;
    id notificationCenterDidFailObserver;
}

@end

@implementation MXKNotificationSettingsViewController

- (void)dealloc
{
    ruleMasterButton = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)destroy
{
    if (notificationCenterWillUpdateObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:notificationCenterWillUpdateObserver];
        notificationCenterWillUpdateObserver = nil;
    }
    
    if (notificationCenterDidUpdateObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:notificationCenterDidUpdateObserver];
        notificationCenterDidUpdateObserver = nil;
    }
    
    if (notificationCenterDidFailObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:notificationCenterDidFailObserver];
        notificationCenterDidFailObserver = nil;
    }
    
    [super destroy];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (_mxAccount)
    {
        [self startActivityIndicator];
        
        // Refresh existing notification rules
        [_mxAccount.mxSession.notificationCenter refreshRules:^{
            
            [self stopActivityIndicator];
            [self.tableView reloadData];
            
        } failure:^(NSError *error) {
            
            [self stopActivityIndicator];
            
        }];
        
        notificationCenterWillUpdateObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXNotificationCenterWillUpdateRules object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [self startActivityIndicator];
        }];
        
        notificationCenterDidUpdateObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXNotificationCenterDidUpdateRules object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [self stopActivityIndicator];
            [self.tableView reloadData];
        }];
        
        notificationCenterDidFailObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXNotificationCenterDidFailRulesUpdate object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [self stopActivityIndicator];
            
            // TODO notify user by using note.userInfo[kMXNotificationCenterErrorKey]
        }];
    }
    
    // Refresh display
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if (notificationCenterWillUpdateObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:notificationCenterWillUpdateObserver];
        notificationCenterWillUpdateObserver = nil;
    }
    
    if (notificationCenterDidUpdateObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:notificationCenterDidUpdateObserver];
        notificationCenterDidUpdateObserver = nil;
    }
    
    if (notificationCenterDidFailObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:notificationCenterDidFailObserver];
        notificationCenterDidFailObserver = nil;
    }
}

#pragma mark - Actions

- (IBAction)onButtonPressed:(id)sender
{
    if (sender == ruleMasterButton)
    {
        // Swap enable state for all noticiations
        MXPushRule *pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterDisableAllNotificationsRuleID];
        if (pushRule)
        {
            [_mxAccount.mxSession.notificationCenter enableRule:pushRule isEnabled:!areAllDisabled];
        }
    }
}

#pragma mark - UITableView data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Check master rule state
    MXPushRule *pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterDisableAllNotificationsRuleID];
    if (pushRule.enabled)
    {
        areAllDisabled = YES;
        return 1;
    }
    else
    {
        areAllDisabled = NO;
        return MXKNOTIFICATIONSETTINGS_SECTION_COUNT;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger count = 0;
    
    if (section == MXKNOTIFICATIONSETTINGS_SECTION_INTRO_INDEX)
    {
        count = 2;
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_PER_WORD_INDEX)
    {
        // A first cell will display a user information
        count = 1;
        
        // Only removable content rules are listed in this section (we ignore here predefined rules)
        for (MXPushRule *pushRule in _mxAccount.mxSession.notificationCenter.rules.global.content)
        {
            if (!pushRule.isDefault)
            {
                count++;
            }
        }
        
        // Add one item to suggest new rule creation
        contentRuleCreationIndex = count ++;
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_PER_ROOM_INDEX)
    {
        count = _mxAccount.mxSession.notificationCenter.rules.global.room.count;
        
        // Add one item to suggest new rule creation
        roomRuleCreationIndex = count ++;
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_PER_SENDER_INDEX)
    {
        count = _mxAccount.mxSession.notificationCenter.rules.global.sender.count;
        
        // Add one item to suggest new rule creation
        senderRuleCreationIndex = count ++;
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_OTHERS_INDEX)
    {
        ruleContainsUserNameIndex = ruleContainsDisplayNameIndex = ruleOneToOneRoomIndex = ruleInviteForMeIndex = ruleMemberEventIndex = ruleCallIndex = ruleSuppressBotsNotificationsIndex = -1;
        
        // Check whether each predefined rule is supported
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterContainUserNameRuleID])
        {
            ruleContainsUserNameIndex = count++;
        }
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterContainDisplayNameRuleID])
        {
            ruleContainsDisplayNameIndex = count++;
        }
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterOneToOneRoomRuleID])
        {
            ruleOneToOneRoomIndex = count++;
        }
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterInviteMeRuleID])
        {
            ruleInviteForMeIndex = count++;
        }
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterMemberEventRuleID])
        {
            ruleMemberEventIndex = count++;
        }
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterCallRuleID])
        {
            ruleCallIndex = count++;
        }
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterSuppressBotsNotificationsRuleID])
        {
            ruleSuppressBotsNotificationsIndex = count++;
        }
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_DEFAULT_INDEX)
    {
        if ([_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterAllOtherRoomMessagesRuleID])
        {
            count = 1;
        }
    }
    
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    NSInteger rowIndex = indexPath.row;
    
    if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_INTRO_INDEX)
    {
        if (indexPath.row == 0)
        {
            MXKTableViewCellWithButton *masterBtnCell = [tableView dequeueReusableCellWithIdentifier:[MXKTableViewCellWithButton defaultReuseIdentifier]];
            if (!masterBtnCell)
            {
                masterBtnCell = [[MXKTableViewCellWithButton alloc] init];
            }
            
            if (areAllDisabled)
            {
                [masterBtnCell.mxkButton setTitle:@"Enable notifications" forState:UIControlStateNormal];
                [masterBtnCell.mxkButton setTitle:@"Enable notifications" forState:UIControlStateHighlighted];
            }
            else
            {
                [masterBtnCell.mxkButton setTitle:@"Disable all notifications" forState:UIControlStateNormal];
                [masterBtnCell.mxkButton setTitle:@"Disable all notifications" forState:UIControlStateHighlighted];
            }
            
            [masterBtnCell.mxkButton addTarget:self action:@selector(onButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
            
            ruleMasterButton = masterBtnCell.mxkButton;
            
            cell = masterBtnCell;
        }
        else
        {
            MXKTableViewCellWithTextView *introCell = [tableView dequeueReusableCellWithIdentifier:[MXKTableViewCellWithTextView defaultReuseIdentifier]];
            if (!introCell)
            {
                introCell = [[MXKTableViewCellWithTextView alloc] init];
            }
            
            if (areAllDisabled)
            {
                introCell.mxkTextView.text = kGlobalNotificationSettingsMainIntroTextWhenDisabled;
                introCell.mxkTextView.backgroundColor = [UIColor redColor];
            }
            else
            {
                introCell.mxkTextView.text = kGlobalNotificationSettingsMainIntroText;
                introCell.mxkTextView.backgroundColor = [UIColor clearColor];
            }
            
            introCell.mxkTextView.font = [UIFont systemFontOfSize:14];
            
            cell = introCell;
        }
    }
    else if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_PER_WORD_INDEX)
    {
        if (rowIndex == 0)
        {
            MXKTableViewCellWithTextView *introCell = [tableView dequeueReusableCellWithIdentifier:[MXKTableViewCellWithTextView defaultReuseIdentifier]];
            if (!introCell)
            {
                introCell = [[MXKTableViewCellWithTextView alloc] init];
            }
            introCell.mxkTextView.text = kGlobalNotificationSettingsPerWordIntroText;
            introCell.mxkTextView.font = [UIFont systemFontOfSize:14];
             
             cell = introCell;
        }
        else if (rowIndex == contentRuleCreationIndex)
        {
            MXKPushRuleCreationTableViewCell *pushRuleCreationCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleCreationTableViewCell defaultReuseIdentifier]];
            if (!pushRuleCreationCell)
            {
                pushRuleCreationCell = [[MXKPushRuleCreationTableViewCell alloc] init];
            }
            
            pushRuleCreationCell.mxSession = _mxAccount.mxSession;;
            pushRuleCreationCell.mxPushRuleKind = MXPushRuleKindContent;
            cell = pushRuleCreationCell;
        }
        else
        {
            // Only removable content rules are listed in this section
            NSInteger count = 0;
            for (MXPushRule *pushRule in _mxAccount.mxSession.notificationCenter.rules.global.content)
            {
                if (!pushRule.isDefault)
                {
                    count++;
                    
                    if (count == rowIndex)
                    {
                        MXKPushRuleTableViewCell *pushRuleCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleTableViewCell defaultReuseIdentifier]];
                        if (!pushRuleCell)
                        {
                            pushRuleCell = [[MXKPushRuleTableViewCell alloc] init];
                        }
                        
                        pushRuleCell.mxSession = _mxAccount.mxSession;
                        pushRuleCell.mxPushRule = pushRule;
                        
                        cell = pushRuleCell;
                        break;
                    }
                }
            }
        }
    }
    else if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_PER_ROOM_INDEX)
    {
        if (rowIndex == roomRuleCreationIndex)
        {
            MXKPushRuleCreationTableViewCell *pushRuleCreationCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleCreationTableViewCell defaultReuseIdentifier]];
            if (!pushRuleCreationCell)
            {
                pushRuleCreationCell = [[MXKPushRuleCreationTableViewCell alloc] init];
            }
            
            pushRuleCreationCell.mxSession = _mxAccount.mxSession;
            pushRuleCreationCell.mxPushRuleKind = MXPushRuleKindRoom;
            cell = pushRuleCreationCell;
        }
        else if (rowIndex < _mxAccount.mxSession.notificationCenter.rules.global.room.count)
        {
            MXKPushRuleTableViewCell *pushRuleCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleTableViewCell defaultReuseIdentifier]];
            if (!pushRuleCell)
            {
                pushRuleCell = [[MXKPushRuleTableViewCell alloc] init];
            }
            
            pushRuleCell.mxSession = _mxAccount.mxSession;
            pushRuleCell.mxPushRule = [_mxAccount.mxSession.notificationCenter.rules.global.room objectAtIndex:rowIndex];
            
            cell = pushRuleCell;
        }
    }
    else if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_PER_SENDER_INDEX)
    {
        if (rowIndex == senderRuleCreationIndex)
        {
            MXKPushRuleCreationTableViewCell *pushRuleCreationCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleCreationTableViewCell defaultReuseIdentifier]];
            if (!pushRuleCreationCell)
            {
                pushRuleCreationCell = [[MXKPushRuleCreationTableViewCell alloc] init];
            }
            
            pushRuleCreationCell.mxSession = _mxAccount.mxSession;
            pushRuleCreationCell.mxPushRuleKind = MXPushRuleKindSender;
            cell = pushRuleCreationCell;
        }
        else if (rowIndex  < _mxAccount.mxSession.notificationCenter.rules.global.sender.count)
        {
            MXKPushRuleTableViewCell *pushRuleCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleTableViewCell defaultReuseIdentifier]];
            if (!pushRuleCell)
            {
                pushRuleCell = [[MXKPushRuleTableViewCell alloc] init];
            }
            
            pushRuleCell.mxSession = _mxAccount.mxSession;
            pushRuleCell.mxPushRule = [_mxAccount.mxSession.notificationCenter.rules.global.sender objectAtIndex:rowIndex];

            cell = pushRuleCell;
        }
    }
    else if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_OTHERS_INDEX)
    {
        MXPushRule *pushRule;
        NSString *ruleDescription;
        
        if (rowIndex == ruleContainsUserNameIndex)
        {
            pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterContainUserNameRuleID];
            ruleDescription = @"Notify me with sound about messages that contain my user name";
        }
        if (rowIndex == ruleContainsDisplayNameIndex)
        {
            pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterContainDisplayNameRuleID];
            ruleDescription = @"Notify me with sound about messages that contain my display name";
        }
        if (rowIndex == ruleOneToOneRoomIndex)
        {
            pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterOneToOneRoomRuleID];
            ruleDescription = @"Notify me with sound about messages sent just to me";
        }
        if (rowIndex == ruleInviteForMeIndex)
        {
            pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterInviteMeRuleID];
            ruleDescription = @"Notify me when I'm invited to a new room";
        }
        if (rowIndex == ruleMemberEventIndex)
        {
            pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterMemberEventRuleID];
            ruleDescription = @"Notify me when people join or leave rooms";
        }
        if (rowIndex == ruleCallIndex)
        {
            pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterCallRuleID];
            ruleDescription = @"Notify me when I receive a call";
        }
        if (rowIndex == ruleSuppressBotsNotificationsIndex)
        {
            pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterSuppressBotsNotificationsRuleID];
            ruleDescription = @"Suppress notifications from bots";
        }
        
        if (pushRule)
        {
            MXKPushRuleTableViewCell *pushRuleCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleTableViewCell defaultReuseIdentifier]];
            if (!pushRuleCell)
            {
                pushRuleCell = [[MXKPushRuleTableViewCell alloc] init];
            }
            
            pushRuleCell.mxSession = _mxAccount.mxSession;
            pushRuleCell.mxPushRule = pushRule;
            pushRuleCell.ruleDescription.text = ruleDescription;
            
            cell = pushRuleCell;
        }
    }
    else if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_DEFAULT_INDEX)
    {
        MXPushRule *pushRule = [_mxAccount.mxSession.notificationCenter ruleById:kMXNotificationCenterAllOtherRoomMessagesRuleID];
        
        if (pushRule)
        {
            MXKPushRuleTableViewCell *pushRuleCell = [tableView dequeueReusableCellWithIdentifier:[MXKPushRuleTableViewCell defaultReuseIdentifier]];
            if (!pushRuleCell)
            {
                pushRuleCell = [[MXKPushRuleTableViewCell alloc] init];
            }
            
            pushRuleCell.mxSession = _mxAccount.mxSession;
            pushRuleCell.mxPushRule = pushRule;
            pushRuleCell.ruleDescription.text = @"Notify for all other messages/rooms";

            cell = pushRuleCell;
        }
    }
    
    return cell;
}

#pragma mark - UITableView delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_INTRO_INDEX && indexPath.row == 1)
    {
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, MAXFLOAT)];
        textView.font = [UIFont systemFontOfSize:14];
        textView.text = areAllDisabled ? kGlobalNotificationSettingsMainIntroTextWhenDisabled : kGlobalNotificationSettingsMainIntroText;
        CGSize contentSize = [textView sizeThatFits:textView.frame.size];
        return contentSize.height + 1;
    }
    
    if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_PER_WORD_INDEX)
    {
        if (indexPath.row == 0)
        {
            UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, MAXFLOAT)];
            textView.font = [UIFont systemFontOfSize:14];
            textView.text = kGlobalNotificationSettingsPerWordIntroText;
            CGSize contentSize = [textView sizeThatFits:textView.frame.size];
            return contentSize.height + 1;
        }
        else if (indexPath.row == contentRuleCreationIndex)
        {
            return 120;
        }
    }
    
    if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_PER_ROOM_INDEX && indexPath.row == roomRuleCreationIndex)
    {
        return 120;
    }
    
    if (indexPath.section == MXKNOTIFICATIONSETTINGS_SECTION_PER_SENDER_INDEX && indexPath.row == senderRuleCreationIndex)
    {
        return 120;
    }
    
    return 50;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section != MXKNOTIFICATIONSETTINGS_SECTION_INTRO_INDEX)
    {
        return 30;
    }
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *sectionHeader = [[UIView alloc] initWithFrame:[tableView rectForHeaderInSection:section]];
    sectionHeader.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
    UILabel *sectionLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, sectionHeader.frame.size.width - 10, sectionHeader.frame.size.height - 10)];
    sectionLabel.font = [UIFont boldSystemFontOfSize:16];
    sectionLabel.backgroundColor = [UIColor clearColor];
    [sectionHeader addSubview:sectionLabel];
    
    if (section == MXKNOTIFICATIONSETTINGS_SECTION_PER_WORD_INDEX)
    {
        sectionLabel.text = @"Per-word notifications";
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_PER_ROOM_INDEX)
    {
        sectionLabel.text = @"Per-room notifications";
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_PER_SENDER_INDEX)
    {
        sectionLabel.text = @"Per-sender notifications";
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_OTHERS_INDEX)
    {
        sectionLabel.text = @"Other Alerts";
    }
    else if (section == MXKNOTIFICATIONSETTINGS_SECTION_DEFAULT_INDEX)
    {
        sectionLabel.text = @"By default...";
    }
    
    return sectionHeader;
}

@end