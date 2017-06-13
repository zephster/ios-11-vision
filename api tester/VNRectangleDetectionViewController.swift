//
//  VNRectangleDetectionViewController.swift
//  api tester
//
//  Created by brandon on 6/12/17.
//  Copyright © 2017 brandon. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class VNRectangleDetectionViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate
{
    // MARK: interface
    @IBOutlet weak var uiPreviewView: UIView!
    @IBOutlet weak var uiSwapCameraButton: UIButton!


    // MARK: ivars
    var captureSession     : AVCaptureSession?
    var videoPreviewLayer  : AVCaptureVideoPreviewLayer?
    var videoConnection    : AVCaptureConnection?
    var requests           = [VNRequest]()
    var isUsingFrontCamera = false


    // MARK: view funcs
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)

        // get permission for camera access
        if AVCaptureDevice.authorizationStatus(for: AVMediaType.video) == .authorized
        {
            self.initCamera()
            self.setupRectangleVision()
        }
        else
        {
            AVCaptureDevice.requestAccess(for: AVMediaType.video)
            {
                response in
                print("requested access")

                if !response {
                    self.backToTestList(title: "no access", message: "need camera access")
                } else {
                    self.initCamera()
                    self.setupRectangleVision()
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        if let session = self.captureSession {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        // reset live previews frame on orientation change
        if let vpl = self.videoPreviewLayer {
            vpl.frame = self.uiPreviewView.bounds
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator)
    {
        // wait for rotation to complete
        coordinator.animate(alongsideTransition: nil)
        {
            _ in

            let orientation:AVCaptureVideoOrientation!

            if let connection = self.videoConnection
            {
                if UIDevice.current.orientation.isLandscape
                {
                    if UIDevice.current.orientation == UIDeviceOrientation.landscapeLeft {
                        orientation = AVCaptureVideoOrientation.landscapeRight
                    }
                    else {
                        orientation = AVCaptureVideoOrientation.landscapeLeft
                    }
                }
                else {
                    orientation = AVCaptureVideoOrientation.portrait
                }

                connection.videoOrientation = orientation
            }
        }
    }

    func backToTestList(title:String, message:String)
    {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "ok", style: .default)
        {
            _ in
            if let session = self.captureSession {
                session.stopRunning()
            }

            self.navigationController?.popViewController(animated: true)
        })

        self.present(alert, animated: true)
    }

    @IBAction func swapCamera(_ sender: UIButton)
    {
        if let session = self.captureSession
        {
            session.stopRunning()

            if self.isUsingFrontCamera {
                self.initCamera(position: "back")
                self.isUsingFrontCamera = false
            }
            else {
                self.initCamera(position: "front")
                self.isUsingFrontCamera = true
            }
        }
    }




    // MARK: init camera
    func initCamera(position:String = "back")
    {
        var captureInput : AVCaptureDeviceInput!
        var captureOutput: AVCaptureVideoDataOutput!
        let captureDevice: AVCaptureDevice!

        // get camera
        if position == "back"
        {
            captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
        }
        else
        {
            captureDevice = AVCaptureDevice.default(
                AVCaptureDevice.DeviceType.builtInWideAngleCamera,
                for: AVMediaType.video,
                position: AVCaptureDevice.Position.front
            )
        }

        guard let camera = captureDevice else {
            self.backToTestList(title: "error", message: "no camera found")
            return
        }

        // init capture session
        self.captureSession = AVCaptureSession()
        guard let session = self.captureSession else {
            self.backToTestList(title: "error", message: "could not init capture session")
            return
        }

        // set up capture input
        do {
            captureInput = try AVCaptureDeviceInput(device: camera)
        }
        catch {
            self.backToTestList(title: "error", message: "error getting device input")
            return
        }

        // add capture input to session
        if session.canAddInput(captureInput) {
            session.addInput(captureInput)
        }
        else {
            self.backToTestList(title: "error", message: "cannot add capture input to session")
            return
        }

        // set up capture output
        captureOutput = AVCaptureVideoDataOutput()
        captureOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))

        // add capture output to session
        if session.canAddOutput(captureOutput) {
            session.addOutput(captureOutput)
        }
        else {
            self.backToTestList(title: "error", message: "cannot add capture output to session")
            return
        }

        // set up live preview
        self.videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)

        guard let previewLayer = self.videoPreviewLayer,
            let videoConnection = previewLayer.connection else {
                return
        }

        // save this reference so i can update the orientation
        self.videoConnection = videoConnection

        // add the preview layer to the preview view
        self.uiPreviewView.layer.addSublayer(previewLayer)

        // start session
        session.startRunning()
    }




    // MARK: delegate funcs
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // todo: eventually phase imageRequestHandler out for sequence handler

        var requestOptions:[VNImageOption:Any] = [:]

        if let cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics:cameraIntrinsicData]
        }

        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
//            orientationu: Int32(UIDevice.current.orientation.rawValue),
            orientation:Int32(UIDeviceOrientation.portrait.rawValue),
            options: requestOptions
        )

        do
        {
            try imageRequestHandler.perform(self.requests)
        }
        catch {
            print(error)
        }
    }




    // MARK: vision prep
    func setupRectangleVision()
    {
        let rectangleDetectionRequest = VNDetectRectanglesRequest(completionHandler: self.handleRectangles)
        rectangleDetectionRequest.minimumSize = 0.1
        rectangleDetectionRequest.maximumObservations = 20
        self.requests.append(rectangleDetectionRequest)
    }




    // MARK: vision handlers
    func handleRectangles(request: VNRequest, error: Error?)
    {
        guard let observations = request.results as? [VNRectangleObservation] else {
            return
        }

        DispatchQueue.main.async {
            self.drawRectangles(observations)
        }
    }


    func drawRectangles(_ rectangles:[VNRectangleObservation])
    {
        // i am positive this is not a great way to go about doing this lol
        if let vpl = self.videoPreviewLayer
        {
            // remove the sublayers excep tht e video preview lol
            for layer in vpl.sublayers! {
                if layer is CAShapeLayer {
                    layer.removeFromSuperlayer()
                }
            }

            for rectangle:VNRectangleObservation in rectangles
            {
                // draw the path of the shape it observed. it's probably a trapezoid. i like that shape.
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rectangle.topLeft.x, y: rectangle.topLeft.y))
                path.addLine(to: CGPoint(x: rectangle.topRight.x, y: rectangle.topRight.y))
                path.addLine(to: CGPoint(x: rectangle.bottomRight.x, y: rectangle.bottomRight.y))
                path.addLine(to: CGPoint(x: rectangle.bottomLeft.x, y: rectangle.bottomLeft.y))
                path.close()

                // all observation position values are 0..1, so scale up to the live preview's size
                path.apply(CGAffineTransform(scaleX: vpl.frame.maxX, y: vpl.frame.maxY))

                //                print(path)

                let fillLayer = CAShapeLayer()
                fillLayer.path = path.cgPath
                fillLayer.fillColor = (UIColor.yellow).cgColor
                fillLayer.opacity = 0.2

                vpl.addSublayer(fillLayer)
            }
        }
    }
}
