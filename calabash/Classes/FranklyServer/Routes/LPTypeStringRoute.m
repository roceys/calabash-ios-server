#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#import "LPTypeStringRoute.h"
#import "LPJSONUtils.h"
#import "LPInvoker.h"
#import "LPInvocationResult.h"
#import "UIScriptParser.h"
#import "LPCocoaLumberjack.h"
#import "LPTouchUtils.h"

static NSString const *LPTypeStringFirstResponderQuery = @"* isFirstResponder:1 index:0";

static CFTimeInterval const LPTypeStringPostKeyDelay = 0.1;

@interface LPTypeStringRoute ()

@property(assign) CFTimeInterval postKeyDelay;

@end

@implementation LPTypeStringRoute

- (instancetype)init {
  self = [super init];
  if (self) {
    _postKeyDelay = LPTypeStringPostKeyDelay;
  }
  return self;
}

- (BOOL) supportsMethod:(NSString *) method atPath:(NSString *) path {
  return [method isEqualToString:@"POST"];
}

- (NSError *)errorWithDescription:(NSString *)description {
  return [NSError errorWithDomain:@"sh.calaba.LPServer"
                             code:1
                         userInfo:@{ NSLocalizedDescriptionKey : description }];
}

- (NSDictionary *)failureResponseWithReason:(NSString *)reason {
  return @{
      @"outcome" : @"FAILURE",
      @"reason" : reason,
      @"details" : @""
  };
}

- (NSDictionary *)successResponseWithResult:(id)result {
  return @{
      @"outcome" : @"SUCCESS",
      @"results" : @[result]
  };
}

- (id)firstResponder {
  NSString *query = @"* isFirstResponder:1 index:0";
  UIScriptParser *parser = [[UIScriptParser alloc] initWithUIScript:query];
  [parser parse];
  NSArray *allWindows = [LPTouchUtils applicationWindows];
  NSArray *results = [parser evalWith:allWindows];
  if (!results || results.count == 0) {
     return nil;
  } else {
     return results[0];
  }
}

// post_key_delay =>
// string =>
- (NSDictionary *) JSONResponseForMethod:(NSString *) method
                                     URI:(NSString *) path
                                    data:(NSDictionary *) data {

  LPLogDebug(@"data: %@", data);

  if (data[@"post_key_delay"]) {
    self.postKeyDelay = (CFTimeInterval)[data[@"post_key_delay"] floatValue];
  }

  LPLogDebug(@"LPTypeString post key delay = %@", @(self.postKeyDelay));

  NSString *reason = @"";

  id target = [self firstResponder];
  if (!target) {
    reason = [NSString stringWithFormat:@"Cannot type text because no view "
                                            " is first responder with query: '%@'",
                                        LPTypeStringFirstResponderQuery];
    LPLogError(@"%@", reason);
    return [self failureResponseWithReason:reason];
  }

  NSString *textToType = data[@"string"];
  if (!textToType) {
    reason = [NSString stringWithFormat:@"Request is missing value for 'string' key"];
    LPLogError(@"%@", reason);
    return [self failureResponseWithReason:reason];
  }


  if (![target conformsToProtocol:@protocol(UITextInputTraits)]) {
    reason = [NSString stringWithFormat:@"View: %@ should conform to UITextInputTraits",
                       target];
    return [self failureResponseWithReason:reason];
  }

  if (![target respondsToSelector:@selector(isFirstResponder)]) {
    reason = [NSString stringWithFormat:@"Target %@ does not respond to "
                                            "'isFirstResponder' selector", target];
    return [self failureResponseWithReason:reason];
  }

  NSError *error = nil;
  if ([target isKindOfClass:[UITextField class]]) {
    BOOL endsWithNewline;
    textToType = [self stringByRemovingTrailingNewline:textToType
                                    hadTrailingNewline:&endsWithNewline
                                                 error:&error];
    if (!textToType) {
      return [self failureResponseWithReason:[error localizedDescription]];
    }
    [self textField:(UITextField *)target typeText:textToType resignAfter:endsWithNewline];
  } else if ([target isKindOfClass:[UITextView class]]) {
    [self textView:(UITextView *)target typeText:textToType];
  } else if ([target isKindOfClass:[UISearchBar class]]) {
    BOOL endsWithNewline;
    textToType = [self stringByRemovingTrailingNewline:textToType
                                    hadTrailingNewline:&endsWithNewline
                                                 error:&error];
    if (!textToType) {
      return [self failureResponseWithReason:[error localizedDescription]];
    }
    [self searchBar:(UISearchBar *)target typeText:textToType resignAfter:endsWithNewline];
  } else {
    LPLogDebug(@"Target class %@ is not a UITextField, UITextView, UISearchBar",
               NSStringFromClass([target class]));
    if (![target conformsToProtocol:@protocol(UIKeyInput)]) {
      reason = [NSString stringWithFormat:@"Target class %@ does not conform to "
                                              "UIKeyInput protocol", [target class]];
      return [self failureResponseWithReason:reason];
    }

    BOOL endsWithNewline;
    textToType = [self stringByRemovingTrailingNewline:textToType
                                    hadTrailingNewline:&endsWithNewline
                                                 error:&error];
    if (!textToType) {
      return [self failureResponseWithReason:[error localizedDescription]];
    }

    [self keyInput:(id<UIKeyInput>)target typeText:textToType resignAfter:endsWithNewline];
  }

  return [self successResponseWithResult:[LPJSONUtils jsonifyObject:target]];
}

- (NSString *)stringByRemovingTrailingNewline:(NSString *)string
                           hadTrailingNewline:(BOOL *)hadTrailing
                                        error:(NSError *__autoreleasing*)error {
  NSString *message = nil;
  NSError *innerError = nil;
  *hadTrailing = NO;
  if ([string containsString:@"\n"]) {
    NSString *replaced = [string stringByReplacingOccurrencesOfString:@"\n"
                                                           withString:@""];
    if ([replaced length] != [string length] - 1) {
      message = [NSString stringWithFormat:@"Cannot type multiple newlines in a UITextField. "
                 "Any newline must be the last character."];
      LPLogError(@"%@", message);
      innerError = [self errorWithDescription:message];
      if (error) { *error = innerError; }
      return nil;
    } else if ([string characterAtIndex:[string length] - 1] != 10) {
      message = [NSString stringWithFormat:@"Cannot type a newline in a UITextField "
                 "unless it is the last character"];
      LPLogError(@"%@", message);
      innerError = [self errorWithDescription:message];
      if (error) { *error = innerError; }
      return nil;
    } else {
      *hadTrailing = YES;
      return replaced;
    }
  } else {
    return [NSString stringWithString:string];
  }
}

#pragma mark - UITextField

- (BOOL)            textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
            replacementString:(NSString *)string {

  id<UITextFieldDelegate> delegate = textField.delegate;

  // There is no delegate, so no delegate methods can be called.
  if (!delegate) { return YES; }

  SEL selector = @selector(textField:shouldChangeCharactersInRange:replacementString:);
  if ([delegate respondsToSelector:selector]) {
    return [delegate textField:textField shouldChangeCharactersInRange:range replacementString:string];
  } else {
    return YES;
  }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  id<UITextFieldDelegate> delegate = textField.delegate;

  // There is no delegate, so no delegate methods can be called.
  if (!delegate) { return YES; }

  SEL selector = @selector(textFieldShouldReturn:);
  if ([delegate respondsToSelector:selector]) {
    return [delegate textFieldShouldReturn:textField];
  } else {
    return YES;
  }
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField {
  id<UITextFieldDelegate> delegate = textField.delegate;

  // There is no delegate, so no delegate methods can be called.
  if (!delegate) { return YES; }

  SEL selector = @selector(textFieldShouldEndEditing:);
  if ([delegate respondsToSelector:selector]) {
    return [delegate textFieldShouldEndEditing:textField];
  } else {
    return YES;
  }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
  id<UITextFieldDelegate> delegate = textField.delegate;

  // There is no delegate, so no delegate methods can be called.
  if (!delegate) { return; }

  SEL selector = @selector(textFieldDidEndEditing:);
  if ([delegate respondsToSelector:selector]) {
    [delegate textFieldDidEndEditing:textField];
  }
}

- (void)textField:(UITextField *)textField
         typeText:(NSString *)textToType
      resignAfter:(BOOL)resignAfter {

  for (NSUInteger index = 0; index < [textToType length]; index++) {
    NSString *existingText = textField.text;

    // Empty text is sometimes represented as nil.
    if (!existingText) { existingText = @""; }

    NSString *nextCharacter = [textToType substringWithRange:NSMakeRange(index, 1)];

    NSRange range;

    // The backspace character.
    if ([nextCharacter isEqualToString:@"\b"]) {
      LPLogDebug(@"Attempting to type backspace");
      // There is no existing text and user sent \b then no delegate methods are called
      // and no notifications are posted.  Continue to the next character, if any, to
      // type.
      if ([existingText isEqualToString:@""]) {
        LPLogDebug(@"Ignoring backspace because there is no text");
        continue;
      }

      nextCharacter = @"";
      range = NSMakeRange([existingText length], 1);
    } else {
      range = NSMakeRange([existingText length], 0);
    }

    if ([self textField:textField shouldChangeCharactersInRange:range replacementString:nextCharacter]) {

      if (![nextCharacter isEqualToString:@""]) {
        [textField insertText:nextCharacter];
      } else {
        [textField deleteBackward];
      }

      [[NSNotificationCenter defaultCenter]
       postNotificationName:UITextFieldTextDidChangeNotification object:textField];
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    } else {
      NSLog(@"Won't type '%@' because delegate return NO when queried.", nextCharacter);
    }
  }

  if (resignAfter) {
    if (![self textFieldShouldReturn:textField]) {
      LPLogDebug(@"Delegate responded with NO when asked 'textFieldShouldReturn:'; "
                 "will not resign first responder");
      return;
    }

    if (![self textFieldShouldEndEditing:textField]) {
      LPLogDebug(@"Delegate responded with NO when asked 'textFieldShouldEndEditing:'; "
                 "will not resign first responder");
      return;
    }

    [textField resignFirstResponder];
    [self textFieldDidEndEditing:textField];
    [[NSNotificationCenter defaultCenter]
     postNotificationName:UITextFieldTextDidEndEditingNotification
     object:textField];
  }
}

#pragma mark - UITextView

- (BOOL)       textView:(UITextView *)textView
shouldChangeTextInRange:(NSRange)range
        replacementText:(NSString *)text {

  id<UITextViewDelegate> delegate = textView.delegate;

  // There is no delegate, so no delegate methods can be called.
  if (!delegate) { return YES; }

  SEL selector = @selector(textView:shouldChangeTextInRange:replacementText:);
  if ([delegate respondsToSelector:selector]) {
    return [delegate textView:textView shouldChangeTextInRange:range replacementText:text];
  } else {
    return YES;
  }
}

- (void)textViewDidChange:(UITextView *)textView {
  id<UITextViewDelegate> delegate = textView.delegate;

  // There is no delegate, so no delegate methods can be called.
  if (!delegate) { return; }

  SEL selector = @selector(textViewDidChange:);
  if ([delegate respondsToSelector:selector]) {
    [delegate textViewDidChange:textView];
  }
}

- (void)textView:(UITextView *)textView typeText:(NSString *)textToType {
  for (NSUInteger index = 0; index < [textToType length]; index++) {
    NSString *existingText = textView.text;

    // Empty text is sometimes represented as nil.
    if (!existingText) { existingText = @""; }

    NSString *nextCharacter = [textToType substringWithRange:NSMakeRange(index, 1)];

    NSRange range;

    // The backspace character.
    if ([nextCharacter isEqualToString:@"\b"]) {
      LPLogDebug(@"Attempting to type backspace");
      // There is no existing text and user sent \b then no delegate methods are called
      // and no notifications are posted.  Continue to the next character, if any, to
      // type.
      if ([existingText isEqualToString:@""]) {
        LPLogDebug(@"Ignoring backspace because there is no text");
        continue;
      }

      nextCharacter = @"";
      range = NSMakeRange([existingText length], 1);
    } else {
      range = NSMakeRange([existingText length], 0);
    }

    if ([self textView:textView shouldChangeTextInRange:range replacementText:nextCharacter]) {
      if (![nextCharacter isEqualToString:@""]) {
        [textView insertText:nextCharacter];
      } else {
        [textView deleteBackward];
      }

      [[NSNotificationCenter defaultCenter]
       postNotificationName:UITextViewTextDidChangeNotification object:textView];
      [self textViewDidChange:textView];
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    } else {
      NSLog(@"Won't type '%@' because delegate return NO when queried.", nextCharacter);
    }
  }
}

#pragma mark - UISearchBar

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
  id<UISearchBarDelegate> delegate = searchBar.delegate;
  if (!delegate) { return; }

  SEL selector = @selector(searchBar:textDidChange:);
  if ([delegate respondsToSelector:selector]) {
    [delegate searchBar:searchBar textDidChange:searchText];
  }
}

- (BOOL)      searchBar:(UISearchBar *)searchBar
shouldChangeTextInRange:(NSRange)range
        replacementText:(NSString *)text {

  id<UISearchBarDelegate> delegate = searchBar.delegate;
  if (!delegate) { return YES; }

  SEL selector = @selector(searchBar:shouldChangeTextInRange:replacementText:);
  if ([delegate respondsToSelector:selector]) {
    return [delegate searchBar:searchBar shouldChangeTextInRange:range replacementText:text];
  } else {
    return YES;
  }
}

- (BOOL)searchBarShouldEndEditing:(UISearchBar *)searchBar {
  id<UISearchBarDelegate> delegate = searchBar.delegate;
  if (!delegate) { return YES; }

  SEL selector = @selector(searchBarShouldEndEditing:);
  if ([delegate respondsToSelector:selector]) {
    return [delegate searchBarShouldEndEditing:searchBar];
  } else {
    return YES;
  }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
  id<UISearchBarDelegate> delegate = searchBar.delegate;
  if (!delegate) { return; }

  SEL selector = @selector(searchBarTextDidEndEditing:);
  if ([delegate respondsToSelector:selector]) {
    [delegate searchBarTextDidEndEditing:searchBar];
  }
}

- (void)searchBar:(UISearchBar *)searchBar
         typeText:(NSString *)textToType
      resignAfter:(BOOL)resignAfter {
  for (NSUInteger index = 0; index < [textToType length]; index++) {
    NSString *existingText = searchBar.text;

    // Empty text is sometimes represented as nil.
    if (!existingText) { existingText = @""; }

    NSString *nextCharacter = [textToType substringWithRange:NSMakeRange(index, 1)];

    NSRange range;

    // The backspace character.
    if ([nextCharacter isEqualToString:@"\b"]) {
      LPLogDebug(@"Attempting to type backspace");

      // There is no existing text and user sent \b then no delegate methods are called
      // and not notifications are posted.  Continue to the next character, if any, to
      // type.
      if ([existingText isEqualToString:@""]) {
        LPLogDebug(@"Ignoring backspace because there is no text");
        continue;
      }

      nextCharacter = @"";
      range = NSMakeRange([existingText length], 1);
    } else {
      range = NSMakeRange([existingText length], 0);
    }

    if ([self searchBar:searchBar shouldChangeTextInRange:range replacementText:nextCharacter]) {
      if (![nextCharacter isEqualToString:@""]) {
        searchBar.text = [NSString stringWithFormat:@"%@%@", existingText, nextCharacter];
      } else {
        if ([existingText length] == 1) {
          searchBar.text = @"";
        } else {
          searchBar.text = [existingText substringToIndex:[existingText length] - 1];
        }
      }
      [self searchBar:searchBar textDidChange:searchBar.text];
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    } else {
      NSLog(@"Won't type '%@' because delegate return NO when queried.", nextCharacter);
    }
  }

  if (resignAfter) {
    if (![self searchBarShouldEndEditing:searchBar]) {
      LPLogDebug(@"Delegate responded with NO when asked 'searchBarShouldEndEditing:'; "
                 "will not resign first responder");
      return;
    }

    [searchBar resignFirstResponder];
    [self searchBarTextDidEndEditing:searchBar];
  }
}

#pragma mark - UIKeyInput

- (void)keyInput:(id<UIKeyInput>)keyInput
        typeText:(NSString *)textToType
     resignAfter:(BOOL)resignAfter {
  for (NSUInteger index = 0; index < [textToType length]; index++) {
    NSString *nextCharacter = [textToType substringWithRange:NSMakeRange(index, 1)];

    // The backspace character.
    if ([nextCharacter isEqualToString:@"\b"]) {
      // There is no existing text and user sent \b then no delegate methods are called
      // and no notifications are posted.  Continue to the next character, if any, to
      // type.
      if (![keyInput hasText]) { continue; }
      [keyInput deleteBackward];
    } else {
      [keyInput insertText:nextCharacter];
    }

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
  }

  if (resignAfter) {
    SEL selector = @selector(resignFirstResponder);
    if ([keyInput respondsToSelector:selector]) {
      LPInvocationResult *invocationResult;
      invocationResult = [LPInvoker invokeOnMainThreadZeroArgumentSelector:selector
                                                                withTarget:keyInput];
      if ([invocationResult isError]) {
        LPLogError(@"Encountered an error calling 'resignFirstResponder' on %@: %@",
                   keyInput, [invocationResult description]);
      }
    } else {
      LPLogDebug(@"Key input: %@ does not respond to 'resignFirstResponder'; will not "
                 "resign first responder", keyInput);
    }
  }
}

@end