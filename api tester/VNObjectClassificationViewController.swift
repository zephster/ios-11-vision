//
//  VNObjectClassificationViewController.swift
//  api tester
//
//  Created by brandon on 6/10/17.
//  Copyright © 2017 brandon. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class VNObjectClassificationViewController: UIViewController
{
    // MARK: interface outlets
    @IBOutlet weak var uiPreviewView: UIView!
    @IBOutlet weak var uiIdentificationLabel: UILabel!
    @IBOutlet weak var uiSwapCameraButton: UIButton!


    // MARK: ivars
    var captureSession     : AVCaptureSession?
    var videoPreviewLayer  : AVCaptureVideoPreviewLayer?
    var videoConnection    : AVCaptureConnection?
    var requests           = [VNRequest]()
    var isUsingFrontCamera = false


    // MARK: view
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.authAndInitCamera()
    }

    override func viewWillDisappear(_ animated: Bool) {
        if let session = self.captureSession {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
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
}




extension VNObjectClassificationViewController
{
    // bail out
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


    // MARK: vision stuff
    func setupClassification()
    {
        do {
            let model = try VNCoreMLModel(for: Inceptionv3().model)
            let request = VNCoreMLRequest(model: model, completionHandler: self.handleClassification)
            self.requests.append(request)
        }
        catch {
            print(error)
        }
    }

    func handleClassification(request: VNRequest, error: Error?)
    {
        guard let observations = request.results as? [VNClassificationObservation] else {
            return
        }

        guard let top = observations.first else {
            return
        }

        DispatchQueue.main.async {
            self.uiIdentificationLabel.text = "classification \(top.identifier) \n confidence \(top.confidence) (\(top.confidence*100)%)"
        }
    }
}



extension VNObjectClassificationViewController: AVCaptureVideoDataOutputSampleBufferDelegate
{
    // MARK: camera stuff
    func authAndInitCamera()
    {
        if AVCaptureDevice.authorizationStatus(for: AVMediaType.video) == .authorized
        {
            self._initCamera()

            // set up vision stuff
            self.setupClassification()
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
                    self._initCamera()

                    // set up vision stuff
                    self.setupClassification()
                }
            }
        }
    }

    @IBAction func swapCamera(_ sender: UIButton)
    {
        if let session = self.captureSession
        {
            session.stopRunning()

            if self.isUsingFrontCamera {
                self._initCamera(position: "back")
                self.isUsingFrontCamera = false
            }
            else {
                self._initCamera(position: "front")
                self.isUsingFrontCamera = true
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // todo: eventually phase imageRequestHandler out for sequence handler.
        // the image handler was being used to process both rectangles and classifications

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

    private func _initCamera(position:String = "back")
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
            captureDevice = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,
                                                    for: AVMediaType.video,
                                                    position: AVCaptureDevice.Position.front)
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
}
