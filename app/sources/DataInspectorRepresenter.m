//
//  DataInspectorRepresenter.m
//  HexFiend_2
//
//  Created by peter on 5/22/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "DataInspectorRepresenter.h"

/* NSTableColumn identifiers */
#define kInspectorTypeColumnIdentifier @"inspector_type"
#define kInspectorSubtypeColumnIdentifier @"inspector_subtype"
#define kInspectorValueColumnIdentifier @"inspected_value"
#define kInspectorSubtractButtonColumnIdentifier @"subtract_button"
#define kInspectorAddButtonColumnIdentifier @"add_button"

#define kScrollViewExtraPadding ((CGFloat)2.)

/* Declaration of SnowLeopard only property so we can build on Leopard */
#define NSTableViewSelectionHighlightStyleNone (-1)

static BOOL isRunningOnLeopardOrLater(void) {
    return NSAppKitVersionNumber >= 860.;
}

NSString * const DataInspectorDidChangeRowCount = @"DataInspectorDidChangeRowCount";
NSString * const DataInspectorDidDeleteAllRows = @"DataInspectorDidDeleteAllRows";

/* Inspector types */
enum InspectorType_t {
    eInspectorTypeInteger,
    eInspectorTypeFloatingPoint
};

enum Endianness_t {
    eEndianBig,
    eEndianLittle,

#if __BIG_ENDIAN__
    eNativeEndianness = eEndianBig
#else
    eNativeEndianness = eEndianLittle
#endif
};

enum InspectionStatus_t {
    eInspectionCanInspect,
    eInspectionNoData,
    eInspectionTooMuchData,
    eInspectionBadByteCount
};

static NSString *errorStringForInspectionStatus(enum InspectionStatus_t status) {
    switch (status) {
	case eInspectionNoData: return @"(select some data)";
	case eInspectionTooMuchData: return @"(select less data)";
	case eInspectionBadByteCount: return @"(select a different number of bytes)";
	default: return nil;
    }
}

/* A class representing a single row of the data inspector */
@interface DataInspector : NSObject {
    enum InspectorType_t inspectorType;
    enum Endianness_t endianness;
}

- (enum InspectorType_t)type;
- (void)setType:(enum InspectorType_t)type;

- (enum Endianness_t)endianness;
- (void)setEndianness:(enum Endianness_t)endianness;

- (enum InspectionStatus_t)inspectionStatusForByteCount:(unsigned long long)count;
- (id)valueForBytes:(const unsigned char *)bytes length:(NSUInteger)length;

/* Returns YES if we can replace the given number of bytes with this string value */
- (BOOL)canAcceptStringValue:(NSString *)value replacingByteCount:(unsigned long long)count;

/* returns YES if types wrapped around */
- (BOOL)incrementToNextType;

@end

@implementation DataInspector


- (void)setType:(enum InspectorType_t)type {
    inspectorType = type;
}

- (enum InspectorType_t)type {
    return inspectorType;
}

- (void)setEndianness:(enum Endianness_t)end {
    endianness = end;
}

- (enum Endianness_t)endianness {
    return endianness;
}

- (NSUInteger)hash {
    return inspectorType + (endianness << 8UL);
}

- (BOOL)isEqual:(DataInspector *)him {
    if (! [him isKindOfClass:[DataInspector class]]) return NO;
    return inspectorType == him->inspectorType && endianness == him->endianness;
}

- (enum InspectionStatus_t)inspectionStatusForByteCount:(unsigned long long)count {
    switch ([self type]) {
        case eInspectorTypeInteger:
            /* Only allow positive powers of 2 up to 8 */
	    switch (count) {
		case 0: return eInspectionNoData;
		case 1: case 2: case 4: case 8: return eInspectionCanInspect;
		default: return (count > 8) ? eInspectionTooMuchData : eInspectionBadByteCount;
	    }
            
        case eInspectorTypeFloatingPoint:
            /* Only 4 and 8 */
	    switch (count) {
		case 0: return eInspectionNoData;
		case 4: case 8: return eInspectionCanInspect;
		default: return (count > 8) ? eInspectionTooMuchData : eInspectionBadByteCount;
	    }
        
        default:
            return NO;
    }
}

static uint64_t reverse(uint64_t val, NSUInteger amount) {
    /* Transfer amount bytes from input to output in reverse order */
    uint64_t input = val, output = 0;
    NSUInteger remaining = amount;
    while (remaining--) {
        unsigned char byte = input & 0xFF;
        output = (output << CHAR_BIT) | byte;
        input >>= CHAR_BIT;
    }
    return output;
}

static id integerDescription(const unsigned char *bytes, NSUInteger length, enum Endianness_t endianness) {
    unsigned long long s = 0;
    switch (length) {
        case 1:
        {
            s = *(const uint8_t *)bytes;
            break;

        }
        case 2:
        {
            s = *(const uint16_t *)bytes;
            break;
        }
        case 4:
        {
            s = *(const uint32_t *)bytes;
            break;
        }
        case 8:
        {
            s = *(const uint64_t *)bytes;
            break;
        }
        default: return nil;
    }
    if (endianness != eNativeEndianness) {
        s = reverse(s, length);
    }
    return [NSString stringWithFormat:@"%lld", s];
}

static id floatingPointDescription(const unsigned char *bytes, NSUInteger length, enum Endianness_t endianness) {
    switch (length) {
        case sizeof(float):
        {
            union {
                uint32_t i;
                float f;
            } temp;
            assert(sizeof temp.f == sizeof temp.i);
            temp.i = *(const uint32_t *)bytes;
            if (endianness != eNativeEndianness) temp.i = (uint32_t)reverse(temp.i, sizeof(float));
            return [NSString stringWithFormat:@"%f", temp.f];
        }
        case sizeof(double):
        {
            union {
                uint64_t i;
                double f;
            } temp;
            assert(sizeof temp.f == sizeof temp.i);
            temp.i = *(const uint64_t *)bytes;
            if (endianness != eNativeEndianness) temp.i = reverse(temp.i, sizeof(double));
            return [NSString stringWithFormat:@"%f", temp.f];
        }
        default: return nil;
    }
}

- (id)valueForBytes:(const unsigned char *)bytes length:(NSUInteger)length {
    assert([self inspectionStatusForByteCount:length] == eInspectionCanInspect);
    switch ([self type]) {
        case eInspectorTypeInteger:
            return integerDescription(bytes, length, endianness);
        
        case eInspectorTypeFloatingPoint:
            return floatingPointDescription(bytes, length, endianness);
            
        default:
            return nil;
    }
}

- (BOOL)incrementToNextType {
    BOOL wrapped = NO;
    if (endianness == eEndianBig) {
	endianness = eEndianLittle;
    }
    else {
	endianness = eEndianBig;
	if (inspectorType == eInspectorTypeInteger) {
	    inspectorType = eInspectorTypeFloatingPoint;
	}
	else {
	    inspectorType = eInspectorTypeInteger;
	    wrapped = YES;
	}
    }
    return wrapped;
}

- (BOOL)canAcceptStringValue:(NSString *)value replacingByteCount:(unsigned long long)count {
    if (inspectorType == eInspectorTypeInteger) {
	char buffer[256];
	BOOL success = [value getCString:buffer maxLength:sizeof buffer encoding:NSASCIIStringEncoding];
	if (! success) return NO;
	
	char *ptr = buffer;
	
	/* allow either signed or unsigned input */
	BOOL useSigned = !! strchr(buffer, '-');
	
	errno = 0;
	char *endPtr = NULL;
	if (useSigned) {
	    strtol(ptr, &endPtr, 0);
	}
	else {
	    strtoull;
	}
    }
    else if (inspectorType == eInspectorTypeFloatingPoint) {
	return YES;
    }
}

@end

@implementation DataInspectorScrollView

- (void)drawDividerWithClip:(NSRect)clipRect {
    [[NSColor lightGrayColor] set];
    NSRect bounds = [self bounds];
    NSRect lineRect = bounds;
    lineRect.size.height = 1;
    NSRectFill(NSIntersectionRect(lineRect, clipRect));
}

- (void)drawRect:(NSRect)rect {
    [[NSColor colorWithCalibratedWhite:(CGFloat).91 alpha:1] set];
    NSRectFill(rect);
    [self drawDividerWithClip:rect];
}

@end

@implementation DataInspectorRepresenter

- (id)init {
    [super init];
    inspectors = [[NSMutableArray alloc] init];
    [self loadDefaultInspectors];
    return self;
}

- (void)loadDefaultInspectors {
    DataInspector *ins = [[DataInspector alloc] init];
    [inspectors addObject:ins];
    [ins release];
}

- (NSView *)createView {
    BOOL loaded = [NSBundle loadNibNamed:@"DataInspectorView" owner:self];
    if (! loaded || ! outletView) {
        [NSException raise:NSInternalInconsistencyException format:@"Unable to load nib named DataInspectorView"];
    }
    NSView *resultView = outletView; //want to inherit its retain here
    outletView = nil;
    if ([table respondsToSelector:@selector(setSelectionHighlightStyle:)]) {
        [table setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
    }
    [table setBackgroundColor:[NSColor colorWithCalibratedWhite:(CGFloat).91 alpha:1]];
    [table setRefusesFirstResponder:YES];
    [table setTarget:self];
    [table setDoubleAction:@selector(doubleClickedTable:)];
    return resultView;
}

+ (NSPoint)defaultLayoutPosition {
    return NSMakePoint(0, (CGFloat)-.5);
}

- (NSUInteger)rowCount {
    return [inspectors count];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    USE(tableView);
    return [self rowCount];
}

static NSAttributedString *inspectionError(NSString *s) {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [paragraphStyle setMinimumLineHeight:(CGFloat)16.];
    NSAttributedString *result = [[NSAttributedString alloc] initWithString:s attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor disabledControlTextColor], NSForegroundColorAttributeName, [NSFont controlContentFontOfSize:11], NSFontAttributeName, paragraphStyle, NSParagraphStyleAttributeName, nil]];
    [paragraphStyle release];
    return result;
}

- (id)valueFromInspector:(DataInspector *)inspector isError:(BOOL *)outIsError{
    HFController *controller = [self controller];
    NSArray *selectedRanges = [controller selectedContentsRanges];
    if ([selectedRanges count] != 1) {
	if (outIsError) *outIsError = YES;
	return inspectionError(@"(select a contiguous range)");
    }

    HFRange selectedRange = [[selectedRanges objectAtIndex:0] HFRange];
    enum InspectionStatus_t inspectionStatus = [inspector inspectionStatusForByteCount:selectedRange.length];
    if (inspectionStatus != eInspectionCanInspect) {
	if (outIsError) *outIsError = YES;
	return inspectionError(errorStringForInspectionStatus(inspectionStatus));
    }
    
    NSData *selection = [controller dataForRange:selectedRange];
    [selection retain];
    const unsigned char *bytes = [selection bytes];
    id result = [inspector valueForBytes:bytes length:ll2l(selectedRange.length)];
    [selection release]; //keep it alive for GC
    if (outIsError) *outIsError = NO;
    return result;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    USE(tableView);
    DataInspector *inspector = [inspectors objectAtIndex:row];
    NSString *ident = [tableColumn identifier];
    if ([ident isEqualToString:kInspectorTypeColumnIdentifier]) {
        return [NSNumber numberWithInt:[inspector type]];
    }
    else if ([ident isEqualToString:kInspectorSubtypeColumnIdentifier]) {
        return [NSNumber numberWithInt:[inspector endianness]];
    }
    else if ([ident isEqualToString:kInspectorValueColumnIdentifier]) {
        return [self valueFromInspector:inspector isError:NULL];
    }
    else if ([ident isEqualToString:kInspectorAddButtonColumnIdentifier] || [ident isEqualToString:kInspectorSubtractButtonColumnIdentifier]) {
        return [NSNumber numberWithInt:1]; //just a button
    }
    else {
        NSLog(@"Unknown column identifier %@", ident);
        return nil;
    }
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *ident = [tableColumn identifier];
    /* This gets called after clicking on the + or - button.  If you delete the last row, then this gets called with a row >= the number of inspectors, so bail out for +/- buttons before pulling out our inspector */
    if ([ident isEqualToString:kInspectorSubtractButtonColumnIdentifier]) return;
    
    DataInspector *inspector = [inspectors objectAtIndex:row];
    if ([ident isEqualToString:kInspectorTypeColumnIdentifier]) {
        [inspector setType:[object intValue]];
        [tableView reloadData];
    }
    else if ([ident isEqualToString:kInspectorSubtypeColumnIdentifier]) {
        [inspector setEndianness:[object intValue]];
        [tableView reloadData];
    }
    else if ([ident isEqualToString:kInspectorValueColumnIdentifier]) {
        
    }
    else if ([ident isEqualToString:kInspectorAddButtonColumnIdentifier] || [ident isEqualToString:kInspectorSubtractButtonColumnIdentifier]) {
        /* Nothing to do */
    }
    else {
        NSLog(@"Unknown column identifier %@", ident);
    }
    
}

- (void)resizeTableViewAfterChangingRowCount {
    [table noteNumberOfRowsChanged];
    NSUInteger rowCount = [table numberOfRows];
    if (rowCount > 0) {
        NSScrollView *scrollView = [table enclosingScrollView];
        NSSize newTableViewBoundsSize = [table frame].size;
        newTableViewBoundsSize.height = NSMaxY([table rectOfRow:rowCount - 1]) - NSMinY([table bounds]);
        /* Is converting to the scroll view's coordinate system right?  It doesn't matter much because nothing is scaled except possibly the window */
        CGFloat newScrollViewHeight = [[scrollView class] frameSizeForContentSize:[table convertSize:newTableViewBoundsSize toView:scrollView]
                                                            hasHorizontalScroller:[scrollView hasHorizontalScroller]
                                                              hasVerticalScroller:[scrollView hasVerticalScroller]
                                                                       borderType:[scrollView borderType]].height + kScrollViewExtraPadding;
        [[NSNotificationCenter defaultCenter] postNotificationName:DataInspectorDidChangeRowCount object:self userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:newScrollViewHeight] forKey:@"height"]];
    }
}

- (void)addRow:(id)sender {
    USE(sender);
    DataInspector *ins = [[DataInspector alloc] init];
    /* Try to add an inspector that we don't already have */
    NSMutableSet *existingInspectors = [[NSMutableSet alloc] initWithArray:inspectors];
    while ([existingInspectors containsObject:ins]) {
	BOOL wrapped = [ins incrementToNextType];
	if (wrapped) break;
    }
    [existingInspectors release];
    
    NSInteger clickedRow = [table clickedRow];
    [inspectors insertObject:ins atIndex:clickedRow + 1];
    [ins release];
    [self resizeTableViewAfterChangingRowCount];
}

- (void)removeRow:(id)sender {
    USE(sender);
    if ([self rowCount] == 1) {
	[[NSNotificationCenter defaultCenter] postNotificationName:DataInspectorDidDeleteAllRows object:self userInfo:nil];
    }
    else {
	NSInteger clickedRow = [table clickedRow];
	[inspectors removeObjectAtIndex:clickedRow];
	[self resizeTableViewAfterChangingRowCount];
    }
}

- (IBAction)doubleClickedTable:(id)sender {
    USE(sender);
    NSInteger column = [table clickedColumn], row = [table clickedRow];
    if (column >= 0 && row >= 0 && [[[[table tableColumns] objectAtIndex:column] identifier] isEqual:kInspectorValueColumnIdentifier]) {
	BOOL isError;
	[self valueFromInspector:[inspectors objectAtIndex:row] isError:&isError];
	if (! isError) {
	    [table editColumn:column row:row withEvent:[NSApp currentEvent] select:YES];
	}
	else {
	    NSBeep();
	}
    }
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor {
    USE(control);
    NSLog(@"%@", [fieldEditor string]);
    NSInteger row = [table editedRow];
    if (row < 0) return YES; /* paranoia */
    DataInspector *inspector = [inspectors objectAtIndex:row];
    return [inspector canAcceptStringValue:[fieldEditor string]];
}


/* Prevent all row selection */

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    /* since shouldTrackCell is only available on 10.5, fall back to crappier behavior on 10.4 */
    USE(tableView);
    USE(row);
    return ! isRunningOnLeopardOrLater();
}

- (BOOL)tableView:(NSTableView *)tableView shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    USE(tableView);
    USE(row);
    USE(cell);
    USE(tableColumn);
    return YES;
}


- (void)refreshTableValues {
    [table reloadData];
}

- (void)controllerDidChange:(HFControllerPropertyBits)bits {
    if (bits & (HFControllerSelectedRanges | HFControllerContentValue)) {
        [self refreshTableValues];
    }
    [super controllerDidChange:bits];
}

@end

@implementation DataInspectorPlusMinusButtonCell

- (id)initWithCoder:(NSCoder *)coder {
    [super initWithCoder:coder];
    [self setBezelStyle:NSRoundRectBezelStyle];
    return self;
}

- (void)drawDataInspectorTitleWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    const BOOL isPlus = [[self title] isEqual:@"+"];
    const unsigned char grayColor = 0x73;
    const unsigned char alpha = 0xFF;
#if __BIG_ENDIAN__
    const unsigned short X = (grayColor << 8) | alpha ;
#else
    const unsigned short X = (alpha << 8) | grayColor;
#endif
    const NSUInteger bytesPerPixel = sizeof X;
    const unsigned short plusData[] = {
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0,
	X,X,X,X,X,X,X,X,
	X,X,X,X,X,X,X,X,
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0,
	0,0,0,X,X,0,0,0
    };
    
    const unsigned short minusData[] = {
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	X,X,X,X,X,X,X,X,
	X,X,X,X,X,X,X,X,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0
    };
    
    const unsigned char * const bitmapData = (const unsigned char *)(isPlus ? plusData : minusData);
    
    NSInteger width = 8, height = 8;
    assert(width * height * bytesPerPixel == sizeof plusData);
    assert(width * height * bytesPerPixel == sizeof minusData);
    NSRect bitmapRect = NSMakeRect(NSMidX(cellFrame) - width/2, NSMidY(cellFrame) - height/2, width, height);
    bitmapRect = [controlView centerScanRect:bitmapRect];

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bitmapData, width * height * bytesPerPixel, NULL);
    CGImageRef image = CGImageCreate(width, height, CHAR_BIT, bytesPerPixel * CHAR_BIT, bytesPerPixel * width, space, kCGImageAlphaPremultipliedLast, provider, NULL, YES, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
    CGContextDrawImage([[NSGraphicsContext currentContext] graphicsPort], *(CGRect *)&bitmapRect, image);
    CGImageRelease(image);
}

- (NSRect)drawTitle:(NSAttributedString*)title withFrame:(NSRect)frame inView:(NSView*)controlView {
    /* Defeat title drawing by doing nothing */
    USE(title);
    USE(frame);
    USE(controlView);
    return NSZeroRect;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [super drawWithFrame:cellFrame inView:controlView];
    [self drawDataInspectorTitleWithFrame:cellFrame inView:controlView];

}

@end

@implementation DataInspectorTableView

- (void)highlightSelectionInClipRect:(NSRect)clipRect {
    USE(clipRect);
}

@end
