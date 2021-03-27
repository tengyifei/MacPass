//
//  MPPasswordInputController.m
//  MacPass
//
//  Created by Michael Starke on 17.02.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#include <Security/Security.h>
#include <Security/SecKeychain.h>

#import "MPPasswordInputController.h"
#import "MPAppDelegate.h"
#import "MPDocumentWindowController.h"
#import "MPDocument.h"
#import "MPSettingsHelper.h"
#import "MPPathControl.h"
#import "MPTouchBarButtonCreator.h"

#import "HNHUi/HNHUi.h"

#import "NSError+Messages.h"

@interface MPPasswordInputController ()

@property (strong) NSButton *showPasswordButton;
@property (weak) IBOutlet HNHUISecureTextField *passwordTextField;
@property (weak) IBOutlet MPPathControl *keyPathControl;
@property (weak) IBOutlet NSImageView *messageImageView;
@property (weak) IBOutlet NSTextField *messageInfoTextField;
@property (strong) IBOutlet NSTextField *keyFileWarningTextField;
@property (weak) IBOutlet NSButton *togglePasswordButton;
@property (weak) IBOutlet NSButton *useKeychainForKeyfileCheckBox;
@property (weak) IBOutlet NSButton *enablePasswordCheckBox;
@property (weak) IBOutlet NSButton *unlockButton;
@property (weak) IBOutlet NSButton *cancelButton;

@property (copy) NSString *message;
@property (copy) NSString *cancelLabel;

@property (assign) BOOL showPassword;
@property (nonatomic, assign) BOOL enablePassword;
@property (copy) passwordInputCompletionBlock completionHandler;

@end

@implementation MPPasswordInputController

- (NSString *)nibName {
  return @"PasswordInputView";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if(self) {
    _enablePassword = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_selectKeyURL) name:MPDidChangeStoredKeyFilesSettings object:nil];
  }
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad {
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(_didSetKeyURL:) name:MPPathControlDidSetURLNotification object:self.keyPathControl];
  self.messageImageView.image = [NSImage imageNamed:NSImageNameCaution];
  [self.passwordTextField bind:NSStringFromSelector(@selector(showPassword)) toObject:self withKeyPath:NSStringFromSelector(@selector(showPassword)) options:nil];
  [self.togglePasswordButton bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(showPassword)) options:nil];
  [self.enablePasswordCheckBox bind:NSValueBinding toObject:self withKeyPath:NSStringFromSelector(@selector(enablePassword)) options:nil];
  [self.togglePasswordButton bind:NSEnabledBinding toObject:self withKeyPath:NSStringFromSelector(@selector(enablePassword)) options:nil];
  [self.passwordTextField bind:NSEnabledBinding toObject:self withKeyPath:NSStringFromSelector(@selector(enablePassword)) options:nil];
  [self _reset];
}

- (NSResponder *)reconmendedFirstResponder {
  return self.passwordTextField;
}

- (void)requestPasswordWithMessage:(NSString *)message cancelLabel:(NSString *)cancelLabel completionHandler:(passwordInputCompletionBlock)completionHandler {
  self.completionHandler = completionHandler;
  self.message = message;
  self.cancelLabel = cancelLabel;
  [self _reset];
}

- (void)requestPasswordWithCompletionHandler:(passwordInputCompletionBlock)completionHandler {
  [self requestPasswordWithMessage:nil cancelLabel:nil completionHandler:completionHandler];
}

#pragma mark Properties
- (void)setEnablePassword:(BOOL)enablePassword {
  if(_enablePassword != enablePassword) {
    _enablePassword = enablePassword;
    if(!_enablePassword) {
      self.passwordTextField.stringValue = @"";
    }
  }
  if(_enablePassword) {
    self.passwordTextField.placeholderString = NSLocalizedString(@"PASSWORD_INPUT_ENTER_PASSWORD", "Placeholder in the unlock-password input field if password is enabled");
  }
  else {
    self.passwordTextField.placeholderString = NSLocalizedString(@"PASSWORD_INPUT_NO_PASSWORD", "Placeholder in the unlock-password input field if password is disabled");
  }
}

#pragma mark -
#pragma mark Private
- (IBAction)_submit:(id)sender {
  if(!self.completionHandler) {
    return;
  }
  
  /* No password is different than an empty password */
  NSError *error = nil;
  NSString *password = self.enablePassword ? self.passwordTextField.stringValue : nil;
  
  BOOL cancel = (sender == self.cancelButton);
  BOOL result = self.completionHandler(password, self.keyPathControl.URL, cancel, &error);
  if(cancel || result) {
    return;
  }
  [self _showError:error];
  /* do not shake if we are a sheet */
  if(!self.view.window.isSheet) {
    [self.view.window shakeWindow:nil];
  }
}

- (IBAction)onToggleKeyChainKeyFile:(id)sender {
  NSLog(@"keychain %ld", (long)self.useKeychainForKeyfileCheckBox.state);
  switch (self.useKeychainForKeyfileCheckBox.state) {
    case NSControlStateValueOn:
      self.keyPathControl.enabled = false;
      self.keyPathControl.editable = false;
      self.keyPathControl.URL = [NSURL URLWithString:@"keychain://keyfile.key"];
      break;
    case NSControlStateValueOff:
      self.keyPathControl.enabled = true;
      self.keyPathControl.editable = true;
      self.keyPathControl.URL = nil;
      break;
    default:
      NSLog(@"warning: unknown keychain state %ld",
            (long)self.useKeychainForKeyfileCheckBox.state);
  }
}

- (IBAction)resetKeyFile:(id)sender {
  /* If the reset was triggered by ourselves we want to preselect the keyfile */
  if(sender == self) {
    [self _selectKeyURL];
  }
  else {
    self.keyPathControl.URL = nil;
    self.useKeychainForKeyfileCheckBox.state = NSControlStateValueOff;
    [self onToggleKeyChainKeyFile: self];
  }
}

- (void)_reset {
  self.showPassword = NO;
  self.enablePassword = YES;
  self.passwordTextField.stringValue = @"";
  self.messageInfoTextField.hidden = (nil == self.message);
  if(self.message) {
    self.messageInfoTextField.stringValue = self.message;
    self.messageImageView.image = [NSImage imageNamed:NSImageNameInfo];
  }
  else {
    self.messageImageView.image = [NSImage imageNamed:NSImageNameCaution];
  }
  self.messageImageView.hidden = (nil == self.message);
  self.cancelButton.hidden = (nil == self.cancelLabel);
  if(self.cancelLabel) {
    self.cancelButton.stringValue = self.cancelLabel;
  }
  [self resetKeyFile:self];
}

- (void)_selectKeyURL {
  MPDocument *document = self.windowController.document;
  self.keyPathControl.URL = document.suggestedKeyURL;
}

- (void)_showError:(NSError *)error {
  if(error) {
    self.messageInfoTextField.stringValue = error.descriptionForErrorCode;
  }
  self.messageImageView.hidden = NO;
  self.messageImageView.image = [NSImage imageNamed:NSImageNameCaution];
  self.messageInfoTextField.hidden = NO;
}


- (NSTouchBar *)makeTouchBar {
  NSTouchBar *touchBar = [[NSTouchBar alloc] init];
  touchBar.delegate = self;
  touchBar.customizationIdentifier = MPTouchBarCustomizationIdentifierPasswordInput;
  NSArray<NSTouchBarItemIdentifier> *defaultItemIdentifiers = @[MPTouchBarItemIdentifierShowPassword, MPTouchBarItemIdentifierChooseKeyfile, NSTouchBarItemIdentifierFlexibleSpace,MPTouchBarItemIdentifierUnlock];
  touchBar.defaultItemIdentifiers = defaultItemIdentifiers;
  touchBar.customizationAllowedItemIdentifiers = defaultItemIdentifiers;
  return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier  API_AVAILABLE(macos(10.12.2)) {
  if (identifier == MPTouchBarItemIdentifierChooseKeyfile) {
    return [MPTouchBarButtonCreator touchBarButtonWithTitleAndImage:NSLocalizedString(@"TOUCHBAR_CHOOSE_KEYFILE","Touchbar button label for choosing the keyfile") identifier:MPTouchBarItemIdentifierChooseKeyfile image:[NSImage imageNamed:NSImageNameTouchBarFolderTemplate] target:self.keyPathControl selector:@selector(showOpenPanel:) customizationLabel:NSLocalizedString(@"TOUCHBAR_CHOOSE_KEYFILE","Touchbar button label for choosing the keyfile")];
  } else if (identifier == MPTouchBarItemIdentifierShowPassword) {
    NSTouchBarItem *item = [MPTouchBarButtonCreator touchBarButtonWithTitleAndImage:NSLocalizedString(@"TOUCHBAR_SHOW_PASSWORD","Touchbar button label for showing the password") identifier:MPTouchBarItemIdentifierShowPassword image:[NSImage imageNamed:NSImageNameTouchBarQuickLookTemplate] target:self selector:@selector(toggleShowPassword) customizationLabel:NSLocalizedString(@"TOUCHBAR_SHOW_PASSWORD","Touchbar button label for showing the password")];
    _showPasswordButton = (NSButton *) item.view;
    return item;
  } else if (identifier == MPTouchBarItemIdentifierUnlock) {
    return [MPTouchBarButtonCreator touchBarButtonWithImage:[NSImage imageNamed:NSImageNameLockUnlockedTemplate] identifier:MPTouchBarItemIdentifierUnlock target:self selector:@selector(_submit:) customizationLabel:NSLocalizedString(@"TOUCHBAR_UNLOCK_DATABASE","Touchbar button label for unlocking the database")];
  } else {
    return nil;
  }
}

- (void)toggleShowPassword {
  self.showPassword = !self.showPassword;
  self.showPasswordButton.bezelColor = self.showPassword ? [NSColor selectedControlColor] : [NSColor controlColor];
}

- (void)_didSetKeyURL:(NSNotification *)notification {
  if(notification.object != self.keyPathControl) {
    return; // wrong sender
  }
  NSDocument *document = (NSDocument *)self.windowController.document;
  NSData *keyFileData = [NSData dataWithContentsOfURL:self.keyPathControl.URL];
  KPKFileVersion keyFileVersion = [KPKFormat.sharedFormat fileVersionForData:keyFileData];
  BOOL isKdbDatabaseFile = (keyFileVersion.format != KPKDatabaseFormatUnknown);
  if(isKdbDatabaseFile) {
    if([document.fileURL isEqual:self.keyPathControl.URL]) {
      self.keyFileWarningTextField.stringValue = NSLocalizedString(@"WARNING_CURRENT_DATABASE_FILE_SELECTED_AS_KEY_FILE", "Error message displayed when the current database file is also set as the key file");
      self.keyFileWarningTextField.hidden = NO;
    }
    else {
      self.keyFileWarningTextField.stringValue = NSLocalizedString(@"WARNING_DATABASE_FILE_SELECTED_AS_KEY_FILE", "Error message displayed when a keepass database file is set as the key file");
      self.keyFileWarningTextField.hidden = NO;
    }
  }
  else {
    self.keyFileWarningTextField.stringValue = @"";
    self.keyFileWarningTextField.hidden = YES;
  }
}


@end

void AddPw() {
  NSString* accountName = @"Yifei.kdbx";
  NSString* serviceName = @"MacPass KeyFile";

  // Replace placeholder key
  NSString* keyHex = @"8BADF00D";

  keyHex = [keyHex stringByReplacingOccurrencesOfString:@" " withString:@""];
  keyHex = [keyHex stringByReplacingOccurrencesOfString:@"\n" withString:@""];
  NSMutableData *keyBin = [[NSMutableData alloc] init];
  unsigned char whole_byte;
  char byte_chars[3] = {'\0','\0','\0'};
  int i;
  for (i=0; i < [keyHex length]/2; i++) {
      byte_chars[0] = [keyHex characterAtIndex:i*2];
      byte_chars[1] = [keyHex characterAtIndex:i*2+1];
      whole_byte = strtol(byte_chars, NULL, 16);
      [keyBin appendBytes:&whole_byte length:1];
  }

  OSStatus status = SecKeychainAddGenericPassword(NULL,
                                                  (UInt32)serviceName.length,
                                                  [serviceName cStringUsingEncoding:NSUTF8StringEncoding],
                                                  (UInt32)accountName.length,
                                                  [accountName cStringUsingEncoding:NSUTF8StringEncoding],
                                                  (UInt32)keyBin.length,
                                                  [keyBin bytes],
                                                  NULL);
  if (status != errSecSuccess) {
    NSLog(@"Error writing to keychain: %d", status);
  }
}

NSData* MPLoadKeyFile(NSURL* keyURL) {
  if (keyURL == nil) {
    return nil;
  }

  NSLog(@"%@", keyURL.absoluteString);
  NSString* urlString = keyURL.absoluteString;
  if (![urlString isEqualToString:@"keychain://keyfile.key"]) {
    return [NSData dataWithContentsOfURL:keyURL];
  }

  // AddPw();

  NSString* accountName = @"Yifei.kdbx";
  NSString* serviceName = @"MacPass KeyFile";
  void * resultBytes = NULL;
  UInt32 resultLength = 0;
  OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                   (UInt32)serviceName.length,
                                                   [serviceName cStringUsingEncoding:NSUTF8StringEncoding],
                                                   (UInt32)accountName.length,
                                                   [accountName cStringUsingEncoding:NSUTF8StringEncoding],
                                                   &resultLength,
                                                   &resultBytes,
                                                   NULL);
  if (status != errSecSuccess) {
    NSLog(@"Error reading from keychain: %d", status);
    return nil;
  }
  NSData *result = [[NSData alloc] initWithBytes:resultBytes
                                          length:resultLength];
  SecKeychainItemFreeContent(NULL, resultBytes);
  return result;
}
