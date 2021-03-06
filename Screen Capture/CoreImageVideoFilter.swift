//
// Copyright 2014 Scott Logic
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import UIKit
import GLKit
import AVFoundation
import CoreMedia
import CoreImage
import OpenGLES
import QuartzCore

class CoreImageVideoFilter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  
    var applyFilter: ((CIImage) -> CIImage?)?
    var videoDisplayView: GLKView!
    var videoDisplayViewBounds: CGRect!
    var renderContext: CIContext!
    private var stillImageOutput: AVCaptureStillImageOutput!
    var avSession: AVCaptureSession?
    var sessionQueue: DispatchQueue!
    var device:AVCaptureDevice? = nil
    
  var detector: CIDetector?
  
  init(superview: UIView, applyFilterCallback: ((CIImage) -> CIImage?)?) {
    self.applyFilter = applyFilterCallback
    videoDisplayView = GLKView(frame: superview.bounds, context: EAGLContext(api: .openGLES2))
    videoDisplayView.transform = CGAffineTransform(rotationAngle: CGFloat(M_PI_2))
    videoDisplayView.frame = superview.bounds
    superview.addSubview(videoDisplayView)
    superview.sendSubview(toBack: videoDisplayView)
    
    renderContext = CIContext(eaglContext: videoDisplayView.context)
    sessionQueue = DispatchQueue(label: "AVSessionQueue", attributes: [])
    
    videoDisplayView.bindDrawable()
    videoDisplayViewBounds = CGRect(x: 0, y: 0, width: videoDisplayView.drawableWidth, height: videoDisplayView.drawableHeight)
  }
  
    deinit {
        stopFiltering()
    }
  
    func takePhoto() {
        
        if let videoConnection = stillImageOutput.connection(withMediaType: AVMediaTypeVideo) {
            stillImageOutput.captureStillImageAsynchronously(from: videoConnection) {
                (imageDataSampleBuffer, error) -> Void in
                
                if(!(error != nil))
                {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    UIImageWriteToSavedPhotosAlbum(UIImage(data: imageData!)!, nil, nil, nil)
                    
                }
                else {
                    self.takePhoto()
                }
            }
        }
        
    }

    func startFiltering() {
    // Create a session if we don't already have one
    if avSession == nil {
      avSession = createAVSession()
        
    
        
        // Set the focus and exposure
        do {
            try device?.lockForConfiguration()
//            avSession?.beginConfiguration()
            
            device?.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            device?.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            
            self.device?.focusMode = AVCaptureFocusMode.locked
            device?.setFocusModeLockedWithLensPosition(0.3, completionHandler: { time in
                
                self.device?.exposureMode = AVCaptureExposureMode.custom
//                let minExposure = self.device?.activeFormat.minExposureDuration
//                let maxExposure = self.device?.activeFormat.maxExposureDuration
                
                let minISO = self.device?.activeFormat.minISO
                self.device?.setExposureModeCustomWithDuration(CMTimeMakeWithSeconds( 0.02, 1000*1000*1000 ), iso: minISO!, completionHandler: { time in
                    
                    
                    self.device?.unlockForConfiguration()
                })
//                self.device?.setExposureTargetBias(0.1, completionHandler: { time in
//                    
////                    self.device?.unlockForConfiguration()
////                    self.avSession?.commitConfiguration()
//                    
//                })
            })
        } catch {}
    }
    
    // And kick it off
    self.avSession?.startRunning()
  }
  
  func stopFiltering() {
    // Stop the av session
    avSession?.stopRunning()
  }
  
  func createAVSession() -> AVCaptureSession {
    // Input from video camera
    
    var input:AVCaptureDeviceInput? = nil
    
    do {
        try device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        try input = AVCaptureDeviceInput(device: device)
    } catch  {
        
    }
    
    // Start out with low quality
    let session = AVCaptureSession()
    session.sessionPreset = AVCaptureSessionPresetPhoto
    
    // Output
    let videoOutput = AVCaptureVideoDataOutput()
    
    videoOutput.videoSettings = [ kCVPixelBufferPixelFormatTypeKey as AnyHashable: kCVPixelFormatType_32BGRA]
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    
    stillImageOutput = AVCaptureStillImageOutput()
    stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
    session.addOutput(stillImageOutput)
    
    // Join it all together
    session.addInput(input)
    session.addOutput(videoOutput)
    return session
  }

  func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
    
    // Need to shimmy this through type-hell
    let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    // Force the type change - pass through opaque buffer
    let opaqueBuffer = Unmanaged<CVImageBuffer>.passUnretained(imageBuffer!).toOpaque()
    let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueBuffer).takeUnretainedValue()
    
    let sourceImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
    
    // Do some detection on the image
    let detectionResult = applyFilter?(sourceImage)
    var outputImage = sourceImage
    if detectionResult != nil {
      outputImage = detectionResult!
    }
    
    // Do some clipping
    var drawFrame = outputImage.extent
    let imageAR = drawFrame.width / drawFrame.height
    let viewAR = videoDisplayViewBounds.width / videoDisplayViewBounds.height
    if imageAR > viewAR {
      drawFrame.origin.x += (drawFrame.width - drawFrame.height * viewAR) / 2.0
      drawFrame.size.width = drawFrame.height / viewAR
    } else {
      drawFrame.origin.y += (drawFrame.height - drawFrame.width / viewAR) / 2.0
      drawFrame.size.height = drawFrame.width / viewAR
    }
    
    videoDisplayView.bindDrawable()
    if videoDisplayView.context != EAGLContext.current() {
      EAGLContext.setCurrent(videoDisplayView.context)
    }
    
    // clear eagl view to grey
    glClearColor(0.5, 0.5, 0.5, 1.0);
    glClear(0x00004000)
    
    // set the blend mode to "source over" so that CI will use that
    glEnable(0x0BE2);
    glBlendFunc(1, 0x0303);
    
    renderContext.draw(outputImage, in: videoDisplayViewBounds, from: drawFrame)
    
    videoDisplayView.display()
    
  }
}
