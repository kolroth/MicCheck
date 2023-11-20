//
//  ViewController.swift
//  MicCheck
//
//  Created by Scott Terry on 11/20/23.
//

import UIKit
import CoreAudioKit
import AVFoundation

enum MicCheckState {
    case idle, recording, playing
}

class ViewController: UIViewController {
    fileprivate var audioEngine: AVAudioEngine!
    fileprivate var audioFile: AVAudioFile?
    fileprivate var audioPlayer: AVAudioPlayerNode!
    fileprivate var mixer: AVAudioMixerNode!
    fileprivate var audioFilePath : String? = nil
    fileprivate var audioOutRef : ExtAudioFileRef? = nil
    
    var audioSession: AVAudioSession!
    var currentState: MicCheckState = .idle
    
    @IBOutlet weak var playBtn: UIButton!
    @IBOutlet weak var recordBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        updateButtons()
        buildAudioEngine()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // check permissions
        if AVAudioApplication.shared.recordPermission != .granted {
            AVAudioApplication.requestRecordPermission { isGranted in
                // done
            }
        }
    }

    @IBAction func playButtonTapped(_ sender: UIButton) {
        // Check if we have something recorded first
        guard audioFilePath != nil else {
            return
        }
        
        // handle play / stop toggle
        if currentState == .idle {
            currentState = .playing
            // start playing
            startPlayback()
        } else if currentState == .playing {
            currentState = .idle
            // stop playing
            stopPlayback()
        }
        updateButtons()
    }
    
    @IBAction func recordButtonTapped(_ sender: UIButton) {
        if currentState == .idle {
            currentState = .recording
            // start recording
            startRecording()
        } else if currentState == .recording {
            currentState = .idle
            // stop recording
            stopRecording()
        }
        updateButtons()
    }
    
    fileprivate func updateButtons() {
        switch currentState {
        case .idle:
            playBtn.isEnabled = true
            recordBtn.isEnabled = true
            playBtn.setTitle("PLAY", for: .normal)
            recordBtn.setTitle("REC", for: .normal)
            playBtn.tintColor = UIColor.green
            recordBtn.tintColor = UIColor.red
        case .recording:
            playBtn.isEnabled = false
            recordBtn.isEnabled = true
            recordBtn.setTitle("STOP", for: .normal)
            recordBtn.tintColor = UIColor.black
        case .playing:
            playBtn.isEnabled = true
            recordBtn.isEnabled = false
            playBtn.setTitle("STOP", for: .normal)
            playBtn.tintColor = UIColor.red
        }
    }
    
    private func startRecording() {
        do {
            try audioSession.setCategory(AVAudioSession.Category.playAndRecord, mode: .voiceChat)
            try audioSession.setActive(true)
            
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: true)!

            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!
            
            let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! as String
            
            audioFilePath = dir.appending("/temp.wav")
                    
            //Create file to save recording
            _ = ExtAudioFileCreateWithURL(
                URL(fileURLWithPath: audioFilePath!) as CFURL,
                kAudioFileWAVEType,
                outputFormat.streamDescription,
                nil,
                AudioFileFlags.eraseFile.rawValue,
                &audioOutRef
            )
            
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) -> Void in
                var newBufferAvailable = true
                    
                let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    if newBufferAvailable {
                        outStatus.pointee = .haveData
                        newBufferAvailable = false
                        
                        return buffer
                    } else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                }
    
                let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(outputFormat.sampleRate) * buffer.frameLength / AVAudioFrameCount(buffer.format.sampleRate))!
    
                var error: NSError?
                _ = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
                    
                _ = ExtAudioFileWrite(self.audioOutRef!, convertedBuffer.frameLength, convertedBuffer.audioBufferList)
            })
            
            try audioEngine.start()
        } catch {
            // handle error
            print("ERROR:: Cannot start recording")
            currentState = .idle
            updateButtons()
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
                
        //Removes tap on Engine Mixer
        audioEngine.inputNode.removeTap(onBus: 0)
        
        //Removes reference to audio file
        ExtAudioFileDispose(audioOutRef!)
        
        //Deactivate audio session
        try! audioSession.setActive(false)
        
        //Reset Engine for next Operation
        buildAudioEngine()
    }
    
    private func startPlayback() {
        do {
            try audioSession.setCategory(AVAudioSession.Category.playback)
            try audioSession.setActive(true)
            
            //Loads audio file
            audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: audioFilePath!))
            
            let audioFormat = audioFile!.processingFormat
            let audioFrameCount = UInt32(audioFile!.length)
            let audioFileBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: audioFrameCount)
            try audioFile!.read(into: audioFileBuffer!)
            
            //Connect audio player to the main mixer node of the engine
            audioEngine.connect(audioPlayer, to: audioEngine.outputNode, format: audioFileBuffer!.format)
            
            //start audio engine
            try audioEngine.start()
            
            //start playing the audio player
            audioPlayer.play()
            audioPlayer.scheduleBuffer(audioFileBuffer!)
        } catch {
            // handle error
            print("ERROR:: Cannot start playback")
            currentState = .idle
            updateButtons()
        }
    }
    
    private func stopPlayback() {
        //Stop the player (if it is playing)
        if audioPlayer.isPlaying {
            audioPlayer.stop()
        }
        
        //Stop the audio engine
        audioEngine.stop()
        
        //Deactivate audio session
        try! audioSession.setActive(false)
        
        //Reset Engine for next Operation
        buildAudioEngine()
    }
    
    private func buildAudioEngine() {
        audioEngine = AVAudioEngine()
        audioPlayer = AVAudioPlayerNode()
        mixer = AVAudioMixerNode()
        audioSession = AVAudioSession.sharedInstance()
        audioEngine.attach(audioPlayer)
        audioEngine.attach(mixer)
    }
}

