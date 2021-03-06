//
//  WCRulerView.m
//  WCEdit
//
//  Created by William Towe on 7/28/14.
//  Copyright (c) 2014 William Towe, LLC. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "WCLineNumbersRulerView.h"
#import <WCFoundation/WCFoundation.h>
#import "WCRulerViewDefaultDataSource.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <ReactiveCocoa/EXTScope.h>
#import "NSTextView+WCExtensions.h"

@interface WCLineNumbersRulerView ()
@property (readwrite,weak,nonatomic) id<WCLineNumbersDataSource> lineNumbersDataSource;
@property (strong,nonatomic) WCRulerViewDefaultDataSource *defaultDataSource;
@end

@implementation WCLineNumbersRulerView
#pragma mark *** Subclass Overrides ***
- (void)dealloc {
    WCLogObject(self.class);
}
#pragma mark NSView
- (BOOL)isOpaque {
    return YES;
}

- (void)viewWillDraw {
    [super viewWillDraw];
    
    CGFloat newThickness = self.requiredThickness;
	
	if (fabs(self.ruleThickness - newThickness) > 1)
		[self setRuleThickness:newThickness];
}
#pragma mark NSRulerView
static CGFloat const kStringMarginLeft = 2.0;
static CGFloat const kStringMarginRight = 4.0;
static NSString *const kDefaultDigit = @"8";

- (CGFloat)requiredThickness {
    NSMutableString *sampleString = [[NSMutableString alloc] init];
    NSUInteger digits = (NSUInteger)log10([self.lineNumbersDataSource numberOfLines]) + 1;
	
    for (NSUInteger i=0; i<digits; i++)
        [sampleString appendString:kDefaultDigit];
    
    NSSize stringSize = [sampleString sizeWithAttributes:self.stringAttributes];
	
	return ceil(stringSize.width + kStringMarginLeft + kStringMarginRight);
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    [self drawBackgroundInRect:rect];
    [self drawLineNumbersInRect:rect];
}
#pragma mark *** Public Methods ***
- (instancetype)initWithScrollView:(NSScrollView *)scrollView lineNumbersDataSource:(id<WCLineNumbersDataSource>)lineNumbersDataSource; {
    if (!(self = [super initWithScrollView:scrollView orientation:NSVerticalRuler]))
        return nil;
    
    NSParameterAssert([scrollView.documentView isKindOfClass:[NSTextView class]]);
    
    [self setClientView:scrollView.documentView];
    
    [self setLineNumbersDataSource:lineNumbersDataSource];
    
    if (!lineNumbersDataSource) {
        [self setDefaultDataSource:[[WCRulerViewDefaultDataSource alloc] initWithRulerView:self]];
        [self setLineNumbersDataSource:self.defaultDataSource];
    }
    
    @weakify(self);
    
    [[[[NSNotificationCenter defaultCenter]
       rac_addObserverForName:NSTextStorageDidProcessEditingNotification object:self.textView.textStorage]
      takeUntil:[self rac_willDeallocSignal]]
     subscribeNext:^(NSNotification *value) {
         @strongify(self);
         
         NSTextStorage *textStorage = value.object;
         
         if ((textStorage.editedMask & NSTextStorageEditedCharacters) == 0)
             return;
         
         [self setNeedsDisplayInRect:self.visibleRect];
     }];
    
    [[[[NSNotificationCenter defaultCenter]
       rac_addObserverForName:NSTextViewDidChangeSelectionNotification object:self.textView]
      takeUntil:[self rac_willDeallocSignal]]
     subscribeNext:^(id _) {
         @strongify(self);
         
         [self setNeedsDisplayInRect:self.visibleRect];
     }];
    
    return self;
}

- (NSRect)lineNumbersRectForRect:(NSRect)rect; {
    return NSMakeRect(NSMinX(rect) + kStringMarginLeft, NSMinY(rect), NSWidth(rect) - kStringMarginLeft - kStringMarginRight, NSHeight(rect));
}

- (NSUInteger)lineNumberForPoint:(NSPoint)point; {
    NSRange charRange = [self.textView WC_visibleRange];
    NSUInteger lineNumber, lineStartIndex;
    
    charRange.length++;
    
    for (lineNumber = [self.lineNumbersDataSource lineNumberForRange:charRange]; lineNumber < [self.lineNumbersDataSource  numberOfLines]; lineNumber++) {
        lineStartIndex = [self.lineNumbersDataSource lineStartIndexForLineNumber:lineNumber];
        
        if (NSLocationInRange(lineStartIndex, charRange)) {
            NSUInteger numberOfLineRects;
            NSRectArray lineRects = [self.textView.layoutManager rectArrayForCharacterRange:[self.textView.string lineRangeForRange:NSMakeRange(lineStartIndex, 0)] withinSelectedCharacterRange:NSMakeRange(NSNotFound, 0) inTextContainer:self.textView.textContainer rectCount:&numberOfLineRects];
            
            if (numberOfLineRects) {
                NSRect lineRect = lineRects[0];
                
                if (numberOfLineRects > 1) {
                    NSUInteger rectIndex;
                    
                    for (rectIndex=1; rectIndex<numberOfLineRects; rectIndex++)
                        lineRect = NSUnionRect(lineRect, lineRects[rectIndex]);
                }
                
                NSRect hitRect = NSMakeRect(NSMinX(self.bounds), [self convertPoint:lineRect.origin fromView:self.clientView].y, NSWidth(self.frame), NSHeight(lineRect));
                
                if (point.y >= NSMinY(hitRect) && point.y < NSMaxY(hitRect))
                    return lineNumber;
            }
        }
        
        if (lineStartIndex > NSMaxRange(charRange))
			break;
    }
    return NSNotFound;
}

- (void)drawBackgroundInRect:(NSRect)rect; {
    [[NSColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0] setFill];
    NSRectFill(rect);
    
    NSRect rightLineRect = NSMakeRect(NSMaxX(self.bounds) - 1, 0, 1, NSHeight(self.frame));
    
    if (NSIntersectsRect(rightLineRect, rect)) {
        [[NSColor lightGrayColor] setFill];
        NSRectFill(rightLineRect);
    }
}
- (void)drawLineNumbersInRect:(NSRect)rect; {
    if (!NSIntersectsRect([self lineNumbersRectForRect:self.bounds], rect))
        return;
    
    NSRange charRange = [self.textView WC_visibleRange];
    NSUInteger lineNumber, lineStartIndex;
    NSIndexSet *selectedLineNumbers = [self selectedLineNumbers];
    NSRect lineNumbersRect = [self lineNumbersRectForRect:self.bounds];
    CGFloat lastLineRectY = -1;
    
    for (lineNumber = [self.lineNumbersDataSource lineNumberForRange:charRange], charRange.length++; lineNumber < [self.lineNumbersDataSource numberOfLines]; lineNumber++) {
        lineStartIndex = [self.lineNumbersDataSource lineStartIndexForLineNumber:lineNumber];
        
        if (NSLocationInRange(lineStartIndex, charRange)) {
            NSUInteger numberOfLineRects;
            NSRectArray lineRects = [self.textView.layoutManager rectArrayForCharacterRange:NSMakeRange(lineStartIndex, 0) withinSelectedCharacterRange:NSMakeRange(NSNotFound, 0) inTextContainer:self.textView.textContainer rectCount:&numberOfLineRects];
            
            if (numberOfLineRects) {
                NSRect lineRect = lineRects[0];
                
                if (NSMinY(lineRect) != lastLineRectY) {
                    NSString *lineNumberString = [NSString stringWithFormat:@"%@",@(lineNumber + 1)];
                    NSDictionary *attributes = ([selectedLineNumbers containsIndex:lineNumber]) ? self.selectedStringAttributes : self.stringAttributes;
                    NSSize stringSize = [lineNumberString sizeWithAttributes:attributes];
                    NSRect drawRect = NSMakeRect(NSMinX(lineNumbersRect), [self convertPoint:lineRect.origin fromView:self.clientView].y + (NSHeight(lineRect) * 0.5) - (stringSize.height * 0.5), NSWidth(lineNumbersRect), NSHeight(lineRect));
                    
                    [lineNumberString drawInRect:drawRect withAttributes:attributes];
                }
                
                lastLineRectY = NSMinY(lineRect);
            }
        }
        
        if (lineStartIndex > NSMaxRange(charRange))
			break;
    }
}
#pragma mark Properties
- (void)setLineNumbersDataSource:(id<WCLineNumbersDataSource>)lineNumbersDataSource {
    _lineNumbersDataSource = lineNumbersDataSource;
    
    if (![self.lineNumbersDataSource isEqual:self.defaultDataSource])
        [self setDefaultDataSource:nil];
}

- (NSTextView *)textView {
    return (NSTextView *)self.clientView;
}

- (NSDictionary *)stringAttributes {
    return @{NSFontAttributeName : [NSFont userFixedPitchFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]], NSForegroundColorAttributeName : [NSColor lightGrayColor], NSParagraphStyleAttributeName : [NSParagraphStyle WC_rightAlignedParagraphStyle]};
}
- (NSDictionary *)selectedStringAttributes {
    return @{NSFontAttributeName : [NSFont userFixedPitchFontOfSize:[NSFont systemFontSizeForControlSize:NSMiniControlSize]], NSForegroundColorAttributeName : [NSColor blackColor], NSParagraphStyleAttributeName : [NSParagraphStyle WC_rightAlignedParagraphStyle]};
}

- (NSIndexSet *)selectedLineNumbers; {
    NSMutableIndexSet *retval = [NSMutableIndexSet indexSet];
    
    NSRange selectedLineRange = [self.textView.string lineRangeForRange:self.textView.selectedRange];
    NSUInteger startLineNumber = [self.lineNumbersDataSource lineNumberForRange:NSMakeRange(selectedLineRange.location, 0)];
    
    if (self.textView.selectedRange.length == 0)
        [retval addIndex:startLineNumber];
    
    return retval;
}

@end
