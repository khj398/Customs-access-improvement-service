import time
import os
from playwright.sync_api import sync_playwright

# AWS Lambdda 저장 경로
#TMP_PATH = "/tmp/"

TMP_PATH = "./downloaded_images/"

# 설정
HEADLESS = False    
TEMP_FILE_PREFIX = "image_"

# 임시 공매 번호, 실제 구현은 파라미터로 받도록 수정
cmdtNm_value = "012-26-01-900027-1"

def main():
    # 저장 폴더 생성
    if not os.path.exists(TMP_PATH):
        os.makedirs(TMP_PATH)

    download_count = 0

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        page = browser.new_page()

        def handle_response(response):
            nonlocal download_count

            url = response.url
            content_type = response.headers.get("content-type", "")

            # 1. URL에 "DOC"가 포함되고 content-type이 image인 경우
            if "DOC" in url and "image" in content_type:
                download_count += 1

                try:
                    # 응답 바디(바이너리 데이터) 가져오기
                    image_buffer = response.body()
                    
                    # 파일명 생성 (URL 마지막 부분 활용 또는 타임스탬프)
                    file_name = url.split("/")[-1].split("?")[0]
                    if not file_name or "." not in file_name:
                        file_name = f"img_{int(time.time() * 1000)}.jpg"
                    
                    file_path = os.path.join(TMP_PATH, file_name)

                    # 이미지 파일 저장
                    with open(file_path, "wb") as f:
                        f.write(image_buffer)
                    
                    print(f"📥 다운로드 완료: {file_name}")
                except Exception as e:
                    print(f"❌ 이미지 저장 실패 ({file_name}): {e}")
                finally:
                    download_count -= 1

        # 리스너 등록
        page.on("response", handle_response)


        page.goto("https://unipass.customs.go.kr/csp/index.do")

        page.evaluate("myc_f_createLeftMenuLst('MYC_MNU_00000634', 'Y')")
        time.sleep(3)
        print("초기 메뉴 로드 완료")
        


        # 물품구분 확인
        # 1: 수입화물(사업자) 2: 휴대품(사업자/개인)
        isBusiness = cmdtNm_value.split("-")[4]

        # 휴대품으로 목록 조회
        if isBusiness == "2":
            page.locator('#MYC0202002Q_cmdtTpcd2').check();
            time.sleep(1)
            page.locator(".search footer button[type='submit']:has-text('조회')").nth(0).click()
            time.sleep(3)

        pages_count = 0
        while True:

            # 페이지 목록 파악
            time.sleep(1)
            page_lists = page.locator(".paging .pages li")
            total_pages = page_lists.count()
            
            for index in range(1, total_pages + 1):
                target_row = page.locator("tr").filter(has=page.locator("td[name='pbacNo']", has_text=cmdtNm_value))
                
                if target_row.count() > 0:
                    print(f"🎯 찾았습니다: {cmdtNm_value}. 클릭합니다.")
                    target_row.locator("a[name='cmdtNm']").click()

                    try:
                        page.wait_for_load_state("networkidle", timeout=30000)
                    except:
                        print("⚠️ 로드 상태 대기 실패")

                else:
                    print(f"{pages_count + index} 페이지에 {cmdtNm_value} 물품이 없습니다. 다음 페이지로 이동합니다.")
                    if index == 10:
                        break
                    else:
                        page_lists.nth(index).click()

                time.sleep(1)

            if page.locator(".paging .next").count() > 0:
                page.locator(".paging .next").click()
                page.wait_for_load_state("networkidle")
                pages_count += 10
            else:   
                break

        while download_count > 0:
            print(f"⏳ 다운로드 대기 중... 남은 다운로드: {download_count}")
            page.wait_for_timeout(500)

        browser.close()

if __name__ == "__main__":
    main()