//
//  VNObjectTrackingViewController.swift
//  api tester
//
//  Created by brandon on 6/10/17.
//  Copyright © 2017 brandon. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class VNObjectTrackingViewController: UIViewController
{
    // MARK: interface outlets
    @IBOutlet weak var uiPreviewView: UIView!
    @IBOutlet weak var uiSwapCameraButton: UIButton!
    @IBOutlet weak var trackingView: UIView?


    // MARK: ivars
    var captureSession     : AVCaptureSession?
    var videoPreviewLayer  : AVCaptureVideoPreviewLayer?
    var videoConnection    : AVCaptureConnection?
    var isUsingFrontCamera = false
    let sequenceHandler    = VNSequenceRequestHandler()
    var lastObservation    : VNDetectedObjectObservation?


    // MARK: view
    override func viewWillAppear(_ animated: Bool)
    {
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




extension VNObjectTrackingViewController
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
    @IBAction private func userTapped(_ sender: UITapGestureRecognizer)
    {
        if let vpl = self.videoPreviewLayer
        {
            guard let trackingView = self.trackingView else {
                return
            }

            // get the center of the tap
            trackingView.frame.size = CGSize(width: 80, height: 80)
            trackingView.center = sender.location(in: self.view)

            trackingView.layer.borderColor = UIColor.cyan.cgColor
            trackingView.layer.borderWidth = 2
            trackingView.layer.backgroundColor = UIColor.clear.cgColor

            // convert the rect for the initial observation
            let originalRect = trackingView.frame
            var convertedRect = vpl.metadataOutputRectConverted(fromLayerRect: originalRect)
            convertedRect.origin.y = 1 - convertedRect.origin.y

            // set the observation
            let newObservation = VNDetectedObjectObservation(boundingBox: convertedRect)
            self.lastObservation = newObservation
        }
    }

    // move tracking rect
    private func handleTrackingRequestUpdate(_ request: VNRequest, error: Error?)
    {
        DispatchQueue.main.async
            {
                guard
                    let newObservation = request.results?.first as? VNDetectedObjectObservation,
                    let trackingView = self.trackingView,
                    let vpl = self.videoPreviewLayer
                    else {
                        return
                }

                // prepare for next loop
                self.lastObservation = newObservation

//                guard newObservation.confidence >= 0.3 else {
//                    vpl.frame = .zero
//                    return
//                }

                // calculate view rect
                // this is some bullshit you have to do to convert between different numeric data types of UIKit <> AVFoundation <> Vision
                var transformedRect = newObservation.boundingBox
                transformedRect.origin.y = 1 - transformedRect.origin.y
                let convertedRect = vpl.layerRectConverted(fromMetadataOutputRect: transformedRect)

                // move the highlight view
                trackingView.frame = convertedRect
        }
    }
}




extension VNObjectTrackingViewController: AVCaptureVideoDataOutputSampleBufferDelegate
{
    // MARK: camera stuff
    func authAndInitCamera()
    {
        if AVCaptureDevice.authorizationStatus(for: AVMediaType.video) == .authorized
        {
            self._initCamera()
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

        // feed last observation into new tracking to have a cycle of tracked objects in sequence
        if let lastObservation = self.lastObservation
        {
            let trackingRequest = VNTrackObjectRequest(detectedObjectObservation: lastObservation, completionHandler: self.handleTrackingRequestUpdate)
            trackingRequest.trackingLevel = .accurate

            do {
                try self.sequenceHandler.perform([trackingRequest], on: pixelBuffer)
            }
            catch {
                print("tracking error \(error)")
            }
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
}
