//
//  ViewController.m
//  TensorFlowLiteDemoObjC
//
//  Created by Bang Chiang Liao on 2019/8/7.
//  Copyright © 2019 Bang Chiang Liao. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <TFLTensorFlowLite/TFLTensorFlowLite.h>

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureDevice *inputDevice;
@property (strong, nonatomic) AVCaptureDeviceInput *deviceInput;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UILabel *messageLabel;
@property (weak, nonatomic) IBOutlet UILabel *fpsLabel;

@property (strong, nonatomic) TFLInterpreter *interpreter;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupInterpreter];
    [self setupCamera];
}

- (void)setupInterpreter {
    NSError *error;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"mobilenet_quant_v1_224" ofType:@"tflite"];
    self.interpreter = [[TFLInterpreter alloc] initWithModelPath:path error:&error];
    
    if (![self.interpreter allocateTensorsWithError:&error]) {
        NSLog(@"Create interpreter error: %@", error);
    }
}

- (void)setupCamera {
    self.session = [[AVCaptureSession alloc] init];
    [self.session setSessionPreset:AVCaptureSessionPresetPhoto];
    
    self.inputDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error;
    self.deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:self.inputDevice error:&error];
    
    if ([self.session canAddInput:self.deviceInput]) {
        [self.session addInput:self.deviceInput];
    }
    
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    CALayer *rootLayer = [[self view] layer];
    [rootLayer setMasksToBounds:YES];
    CGRect frame = self.view.frame;
    [self.previewLayer setFrame:frame];
    [rootLayer insertSublayer:self.previewLayer atIndex:0];
    
    AVCaptureVideoDataOutput *videoDataOutput = [AVCaptureVideoDataOutput new];
    
    NSDictionary *rgbOutputSettings = [NSDictionary
                                       dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA]
                                       forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [videoDataOutput setVideoSettings:rgbOutputSettings];
    [videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    dispatch_queue_t videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
    [videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
    
    if ([self.session canAddOutput:videoDataOutput])
        [self.session addOutput:videoDataOutput];
    [[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
    
    [self.session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef cvImage = CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:cvImage];
    
    
    size_t height = CVPixelBufferGetHeight(cvImage);
    size_t width = CVPixelBufferGetWidth(cvImage);
    
    CGRect videoRect = CGRectMake(0, 0, width, height);
    CGSize scaledSize = CGSizeMake(224, 224);
    
    // Create a rectangle that meets the output size's aspect ratio, centered in the original video frame
    CGRect centerCroppingRect = AVMakeRectWithAspectRatioInsideRect(scaledSize, videoRect);
    
    CVPixelBufferRef croppedAndScaled = [self createCroppedPixelBufferRef:cvImage cropRect:centerCroppingRect scaleSize:scaledSize context:nil];
    NSData *imageData = [self dataFromPixelBufferRef:croppedAndScaled];
    
    NSError *error;
    TFLTensor *inputTensor = [self.interpreter inputTensorAtIndex:0 error:&error];
    [inputTensor copyData:imageData error:&error];
    
    [self.interpreter invokeWithError:&error];
    TFLTensor *outputTensor = [self.interpreter outputTensorAtIndex:0 error:&error];
    
    if (error) {
        NSLog(@"Error: %@", error);
    }
}

- (NSData *)dataFromPixelBufferRef:(CVPixelBufferRef)pixelBufferRef {
    CVPixelBufferLockBaseAddress(pixelBufferRef, 0);
    void *buffer = CVPixelBufferGetBaseAddress(pixelBufferRef);
    size_t length = CVPixelBufferGetDataSize(pixelBufferRef);
    CVPixelBufferUnlockBaseAddress(pixelBufferRef, 0);
    
    NSData *data = [NSData dataWithBytes:buffer length:length];
    return data;
}

//- (CVPixelBufferRef)cropAndCenteredPixelBufferRef:(CVPixelBufferRef)pixelBufferRef width:(CGFloat)width height:(CGFloat)height {
//
//}

- (CVPixelBufferRef)createCroppedPixelBufferRef:(CVPixelBufferRef)pixelBuffer cropRect:(CGRect)cropRect scaleSize:(CGSize)scaleSize context:(CIContext *)context {
    //    assertCropAndScaleValid(pixelBuffer, cropRect, scaleSize);
    
    CIImage *image = [CIImage imageWithCVImageBuffer:pixelBuffer];
    image = [image imageByCroppingToRect:cropRect];
    
    CGFloat scaleX = scaleSize.width / CGRectGetWidth(image.extent);
    CGFloat scaleY = scaleSize.height / CGRectGetHeight(image.extent);
    
    image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scaleX, scaleY)];
    
    // Due to the way [CIContext:render:toCVPixelBuffer] works, we need to translate the image so the cropped section is at the origin
    image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-image.extent.origin.x, -image.extent.origin.y)];
    
    CVPixelBufferRef output = NULL;
    
    CVPixelBufferCreate(nil,
                        CGRectGetWidth(image.extent),
                        CGRectGetHeight(image.extent),
                        CVPixelBufferGetPixelFormatType(pixelBuffer),
                        nil,
                        &output);
    
    if (output != NULL) {
        [context render:image toCVPixelBuffer:output];
    }
    
    return output;
}

@end
