import requests
import json

LAMBDA_URL = "https://fkvdjeiqfyktegxgnllvyrt37y0xrcvc.lambda-url.ap-northeast-2.on.aws/"

target_group_1 = [
    "02026029000061", "04126019000021"
]

target_group_1 = list(set(target_group_1))

payload = {
    "targets": target_group_1
}

def send_test_request():
    print(f"람다로 요청을 보냅니다... (대상 개수: {len(target_group_1)}개)")
    
    try:
        response = requests.post(
            LAMBDA_URL, 
            data=json.dumps(payload),
            headers={'Content-Type': 'application/json'},
            timeout=5 
        )
        
        print(f"상태 코드: {response.status_code}")
        print(f"응답 내용: {response.text}")
        
    except requests.exceptions.ReadTimeout:
        print("경고: 요청 타임아웃 발생 (하지만 람다는 실행 중일 수 있습니다).")
    except Exception as e:
        print(f"에러 발생: {e}")

if __name__ == "__main__":
    send_test_request()