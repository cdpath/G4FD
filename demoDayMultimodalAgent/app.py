from flask import Flask, request, jsonify
import os
from datetime import datetime, timedelta
import requests
import base64
from mimetypes import guess_type

env = os.environ.get


app = Flask(__name__)

# Configuration
UPLOAD_FOLDER = 'uploads'
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

API_KEY = env("AZURE_OPENAI_API_KEY")
ENDPOINT = env("AZURE_OPENAI_ENDPOINT")

# Add cache to store the latest result
latest_analysis = {
    'description': None,
    'timestamp': None
}

def local_image_to_data_url(image_path):
    """
    Get the url of a local image
    """
    mime_type, _ = guess_type(image_path)

    if mime_type is None:
        mime_type = "application/octet-stream"

    with open(image_path, "rb") as image_file:
        base64_encoded_data = base64.b64encode(image_file.read()).decode("utf-8")

    return f"data:{mime_type};base64,{base64_encoded_data}"


def analyze_image(image_path):
    """使用 Azure OpenAI 服务分析图像"""
    try:
        headers = {
            "Content-Type": "application/json",
            "api-key": API_KEY,
        }

        payload = {
            "messages": [
                {
                    "role": "system",
                    "content": [
                        {
                            "type": "text",
                            "text": "你是一个帮助盲人分析图片中主体的 AI 助手。请直接给出图片中最重要的主体的名字即可。不需要其他任何解释和前缀。"
                        }
                    ]
                },
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "请说出这张图片的主体"
                        },
                        {
                            "type": "image_url",
                            "image_url": {"url": local_image_to_data_url(image_path)},
                        }
                    ]
                }
            ],
            "temperature": 0.7,
            "top_p": 0.95,
            "max_tokens": 800
        }

        response = requests.post(ENDPOINT, headers=headers, json=payload)
        response.raise_for_status()
        
        result = response.json()
        # 提取 AI 的响应
        description = result['choices'][0]['message']['content']
        # Update the cache with latest result
        global latest_analysis
        latest_analysis = {
            'description': description,
            'timestamp': datetime.now().isoformat()
        }
        return description

    except Exception as e:
        app.logger.error(f"Image analysis failed: {str(e)}")
        return f"分析失败: {str(e)}"

@app.route('/analyze', methods=['POST'])
def analyze():
    try:
        request_size = request.content_length
        app.logger.info(f"Received request of size: {request_size} bytes")

        if 'image' not in request.files:
            return jsonify({'error': '没有收到图片文件'}), 400

        file = request.files['image']
        if file.filename == '':
            return jsonify({'error': '文件名为空'}), 400

        # 生成唯一的文件名
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"image_{timestamp}.jpg"
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        app.logger.info("Saved image to %s", filepath)

        # 保存文件
        file.save(filepath)

        # 分析图像
        description = analyze_image(filepath)

        # 可选：删除临时文件
        # os.remove(filepath)

        return jsonify({
            'description': description,
            'timestamp': timestamp
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/latest', methods=['GET'])
def get_latest():
    """Get the latest analysis result"""
    if latest_analysis['description'] is None:
        return jsonify({'error': '没有可用的分析结果'}), 404
    
    # Calculate how old the result is
    last_update = datetime.fromisoformat(latest_analysis['timestamp'])
    age = datetime.now() - last_update
    
    return jsonify({
        'description': latest_analysis['description'],
        'timestamp': latest_analysis['timestamp'],
        'age_seconds': age.total_seconds()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8123)
