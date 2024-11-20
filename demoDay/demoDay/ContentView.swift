//
//  ContentView.swift
//  demoDay
//
//  Created on 2024/11/14.
//

import SwiftUI
import AVFoundation
import LiveKit
import LiveKitComponents

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var connectionManager = RoomConnectionManager()
    @State private var environmentDescription: String = "等待环境描述..."
    @State private var timer: Timer?
    
    // LiveKit 配置
    let wsURL = "<Replace with your own>"
    let token = "<Replace with your own>"

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧相机预览
                CameraPreviewView(session: cameraManager.session)
                    .frame(width: geometry.size.width * 0.5, height: geometry.size.height)
                    .rotationEffect(.degrees(90)) // 添加旋转效果
                    // .background(Color.black)
                    // .border(Color.red, width: 1)
                
                // 右侧内容
                VStack {
                    // 上半部分：环境描述
                    VStack {
                        Text("当前环境:")
                            .font(.headline)
                        Text(environmentDescription)
                            .font(.body)
                    }
                    .frame(maxHeight: geometry.size.height * 0.5)
                    
                    // 下半部分：语音助手
                    VoiceAssistantView(connectionManager: connectionManager)
                        .frame(maxHeight: geometry.size.height * 0.5)
                }
                .frame(width: geometry.size.width * 0.5)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            print("视图出现，开始设置")
            cameraManager.checkPermissionAndSetupSession()
        }
        // 监听相机会话状态
        .onChange(of: cameraManager.isSessionReady) { oldValue, newValue in
            if newValue {
                print("相机会话就绪，开始设置定时器和首次分析")
                setupTimer()
                // 立即执行一次分析
                Task {
                    await captureAndAnalyzeFrame()
                }
            }
        }
        .onDisappear {
            // 清理定时器
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func setupTimer() {
        print("设置定时器")
        timer?.invalidate() // 确保不会创建多个定时器
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            print("定时器触发")
            Task {
                await captureAndAnalyzeFrame()
            }
        }
    }
    
    private func captureAndAnalyzeFrame() async {
        print("开始捕获和分析帧")
        guard cameraManager.isSessionReady else {
            print("相机会话未就绪，跳过捕获")
            return
        }
        
        do {
            if let image = await cameraManager.captureFrame() {
                print("成功捕获图像")
                environmentDescription = "正在分析环境..."
                let description = try await sendImageToAPI(image: image)
                print("收到API响应: \(description)")
                DispatchQueue.main.async {
                    self.environmentDescription = description
                }
            } else {
                print("捕获图像失败")
            }
        } catch {
            print("分析过程出错: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.environmentDescription = "分析失败: \(error.localizedDescription)"
            }
        }
    }
}

// 简化 CameraPreviewView
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        print("开始创建预览视图")
        let view = UIView()
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        
        // 重置所有旋转设置
        if let connection = previewLayer.connection {
            connection.videoRotationAngle = 0
            connection.isVideoMirrored = true
        }
        
        view.layer.addSublayer(previewLayer)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else {
            print("无法获取预览层")
            return
        }
        
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
}

// 相机管理器
class CameraManager: ObservableObject {
    let session = AVCaptureSession()
    private var output = AVCapturePhotoOutput()
    @Published var isSessionReady = false  // 添加状态标志
    
    func checkPermissionAndSetupSession() {
        print("开始检查相机和音频权限")
        DispatchQueue.main.async { [weak self] in
            // Check audio permission first
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    print("音频权限已授权")
                    // Then check camera permission
                    switch AVCaptureDevice.authorizationStatus(for: .video) {
                    case .authorized:
                        print("相机权限已授权")
                        self?.setupSession()
                    case .notDetermined:
                        print("请求相机权限")
                        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                            if granted {
                                DispatchQueue.main.async {
                                    print("用户授权了相机权限")
                                    self?.setupSession()
                                }
                            } else {
                                print("用户拒绝了相机权限")
                            }
                        }
                    default:
                        print("相机权限被拒绝或受限")
                        break
                    }
                } else {
                    print("音频权限被拒绝")
                }
            }
        }
    }
    
    private func setupSession() {
        print("开始设置相机会话")
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { 
            print("获取相机设备或输入失败")
            return 
        }
        
        session.beginConfiguration()
        
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        
        if session.canAddInput(input) && session.canAddOutput(output) {
            session.addInput(input)
            session.addOutput(output)
            
            if let connection = output.connection(with: .video) {
                connection.videoRotationAngle = 0
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                    print("设置视频镜像")
                }
            }
            
            session.commitConfiguration()
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                print("启动相机会话")
                self?.session.startRunning()
                DispatchQueue.main.async {
                    self?.isSessionReady = true  // 标记会话已准备就绪
                    print("相机会话已准备就绪")
                }
            }
        }
    }
    
    func captureFrame() async -> UIImage? {
        print("开始捕获相机帧")
        
        // 确保相机会话正在运行
        guard session.isRunning else {
            print("相机会话未运行")
            return nil
        }
        
        let photoSettings = AVCapturePhotoSettings()
        
        return await withCheckedContinuation { continuation in
            let photoOutput = self.output
            
            class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
                let completion: (UIImage?) -> Void
                
                init(completion: @escaping (UIImage?) -> Void) {
                    self.completion = completion
                    super.init()
                    print("创建照片捕获代理")
                }
                
                func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
                    print("照片处理完成")
                    if let error = error {
                        print("照片处理错误: \(error.localizedDescription)")
                        completion(nil)
                        return
                    }
                    
                    guard let imageData = photo.fileDataRepresentation(),
                          let image = UIImage(data: imageData) else {
                        print("无法从照片数据创建图像")
                        completion(nil)
                        return
                    }
                    print("成功创建图像")
                    completion(image)
                }
            }
            
            let delegate = PhotoCaptureDelegate { image in
                print("照片捕获完成，准备继续")
                continuation.resume(returning: image)
            }
            
            // 保持delegate引用
            objc_setAssociatedObject(photoOutput, "PhotoDelegate\(UUID().uuidString)", delegate, .OBJC_ASSOCIATION_RETAIN)
            
            print("开始捕获照片")
            photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
        }
    }
}

// 添加网络请求相关的代码
struct APIResponse: Codable {
    let description: String
    let timestamp: String
}

func sendImageToAPI(image: UIImage) async throws -> String {
    print("准备发送图像到API")
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        print("转换图像为JPEG失败")
        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
    }
    
    print("图像大小: \(imageData.count) bytes")
    
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: URL(string: "http://<Replace with your own>/analyze")!)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(imageData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    
    request.httpBody = body
    
    print("开始发送网络请求")
    let (data, response) = try await URLSession.shared.data(for: request)
    print("收到网络响应: \(response)")
    
    let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
    print("解析响应成功: \(apiResponse)")
    return apiResponse.description
}

#Preview {
    ContentView()
}
