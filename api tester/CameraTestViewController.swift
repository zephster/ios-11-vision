//
//  CameraTestViewController.swift
//  api tester
//
//  Created by brandon on 6/10/17.
//  Copyright © 2017 brandon. All rights reserved.
//

import UIKit
import AVFoundation

class CameraTestViewController: UIViewController
{
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var captureImageView: UIImageView!

    var session: AVCaptureSession?
    var stillImageOutput: AVCapturePhotoOutput?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    func initCamera()
    {
        print("+++++ init camera +++++")

        self.session = AVCaptureSession()
        let backCamera = AVCaptureDevice.default(for: AVMediaType.video)
        
        var error: NSError?
        var input: AVCaptureDeviceInput!

        do {
            guard let camera = backCamera else
            {
                let alert = UIAlertController(
                    title: "no camera",
                    message: "no camera found",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "ok", style: .default)
                {
                    _ in
                    self.navigationController?.popViewController(animated: true)
                })
                
                self.present(alert, animated: true)
                return
            }
            
            input = try AVCaptureDeviceInput(device: camera)
        } catch let error1 as NSError {
            error = error1
            input = nil
            print(error!.localizedDescription)
        }

        if error == nil && session!.canAddInput(input) {
            session!.addInput(input)

            stillImageOutput = AVCapturePhotoOutput()

            if session!.canAddOutput(stillImageOutput!) {
                session!.addOutput(stillImageOutput!)
                videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session!)
                videoPreviewLayer!.videoGravity = AVLayerVideoGravity.resizeAspect
                videoPreviewLayer!.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
                previewView.layer.addSublayer(videoPreviewLayer!)
                session!.startRunning()
            }
            
            
        }
    }
    

    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)

        AVCaptureDevice.requestAccess(for: AVMediaType.video)
        {
            response in

            print("requested access")

            if !response
            {
                let alert = UIAlertController(
                    title: "no access",
                    message: "need camera access",
                    preferredStyle: .alert
                )

                alert.addAction(UIAlertAction(title: "ok", style: .default)
                {
                    _ in
                    self.navigationController?.popViewController(animated: true)
                })

                self.present(alert, animated: true)
            }
        }

        self.initCamera()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let vpl = videoPreviewLayer {
            vpl.frame = previewView.bounds
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
