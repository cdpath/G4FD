import requests
import json
import time

def test_local_image(image_path):
    # Local Flask server URL
    url = "http://localhost:8123/analyze"
    
    # Open and prepare the image file
    with open(image_path, 'rb') as img:
        files = {
            'image': (image_path, img, 'image/jpeg')
        }
        
        # Send POST request to your Flask endpoint
        response = requests.post(url, files=files)
        
        # Print the response
        print("Status Code:", response.status_code)
        print("Response:", json.dumps(response.json(), ensure_ascii=False, indent=2))


def test_get_latest_result():
    url = "http://localhost:8123/analyze"
    resp = requests.get(url)
    print(resp.json())
    # {'age_seconds': 2.059143, 'description': '黄瓜', 'timestamp': '2024-11-20T03:46:43.967507'}


if __name__ == "__main__":
    # Replace with your image path
    image_path = "./D3B6C67A-47E3-43BD-AC36-CA699F394482_1_105_c.jpeg"
    test_local_image(image_path) 
    time.sleep(2)
    test_get_latest_result()
