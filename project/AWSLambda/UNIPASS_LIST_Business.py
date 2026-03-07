import json
import os
from playwright.sync_api import sync_playwright

# AWS Lambdda 저장 경로
#TMP_PATH = "/tmp/"

TMP_PATH = "./"

# 설정
HEADLESS = False             
KEYWORD = "retrievePbacCmdt.do"     
TEMP_FILE_PREFIX = "b_temp_page_"
FINAL_FILE = "unipass_all_2b.json" 

# 페이지 응답 JSON 저장
def save_temp_json(response, index):
    try:
        data = response.json()
        items = data.get("items", [])       # items 키의 값 추출 (실제 물품 목록 데이터)
        filename = os.path.join(TMP_PATH, f"{TEMP_FILE_PREFIX}{index}.json")
        with open(filename, "w", encoding="utf-8") as f:
            json.dump(items, f, ensure_ascii=False, indent=4)
        return True
    
    except Exception as e:
        print(f"{index} 페이지 저장 중 에러: {e}")
        return False

# 임시 JSON 파일 통합 및 정리
def merge_and_cleanup(total_count):
    all_data = []
    
    for i in range(1, total_count + 1):
        filename = os.path.join(TMP_PATH, f"{TEMP_FILE_PREFIX}{i}.json")
        if os.path.exists(filename):
            with open(filename, "r", encoding="utf-8") as f:
                page_data = json.load(f)
                all_data.extend(page_data)
            
            os.remove(filename)
            print(f"{filename} 통합 및 삭제 완료")

    with open(FINAL_FILE, "w", encoding="utf-8") as f:
        json.dump(all_data, f, ensure_ascii=False, indent=4)
    
    print(f"\n최종 통합 완료: {FINAL_FILE} (총 {len(all_data)}건)")

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        page = browser.new_page()

        print("Unipass 접속 및 초기 데이터 수신...")
        page.goto("https://unipass.customs.go.kr/csp/index.do")

        # 물품 조회 페이지 이동
        with page.expect_response(lambda r: KEYWORD in r.url) as resp:
            page.evaluate("myc_f_createLeftMenuLst('MYC_MNU_00000634', 'Y')")

        pages_count = 0
        while True:
            # 초기 페이지
            save_temp_json(resp.value, pages_count + 1)

            # 페이지 목록 파악
            page.wait_for_timeout(1000)
            page_lists = page.locator(".paging .pages li")
            total_pages = page_lists.count()
            
            # 다음 페이지부터
            for index in range(2, total_pages + 1):
                with page.expect_response(lambda r: KEYWORD in r.url) as resp:
                    page_lists.nth(index - 1).click()
                save_temp_json(resp.value, pages_count + index)
                page.wait_for_timeout(1000)

            if page.locator(".paging .next").count() > 0:
                with page.expect_response(lambda r: KEYWORD in r.url) as new_resp:
                    page.locator(".paging .next").click()
                resp = new_resp
                page.wait_for_load_state("networkidle")
                pages_count += 10
            else:
                break
                
        browser.close()
        
        merge_and_cleanup(pages_count + total_pages if pages_count + total_pages > 0 else 1)

if __name__ == "__main__":
    main()