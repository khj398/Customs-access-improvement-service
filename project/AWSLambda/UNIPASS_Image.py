import os
from playwright.sync_api import sync_playwright

# AWS Lambdda 저장 경로
#TMP_PATH = "/tmp/"

TMP_PATH = "./downloaded_images/"

# 설정
HEADLESS = False

# 임시 공매 번호, 실제 구현은 파라미터로 받도록 수정
cmdtNm_value = "020-26-01-900003-1"

def main():
    # 저장 폴더 생성
    if not os.path.exists(TMP_PATH):
        os.makedirs(TMP_PATH)

    downloadCount = 0
    pbacNo = 0      # 유니패스 데이터베이스 속성명
    cmdtLnNo = 1
    imageCount = 0

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        page = browser.new_page()

        def handle_response(response):
            nonlocal downloadCount      # 이미지 저장 락
            nonlocal pbacNo     # 공매번호 입력매개변수
            nonlocal cmdtLnNo
            nonlocal imageCount

            url = response.url
            content_type = response.headers.get("content-type", "")

            # URL에 "DOC"가 포함되고 content-type이 image인 경우
            if "DOC" in url and "image" in content_type:
                downloadCount += 1
                currentIndex = imageCount
                imageCount += 1

                # 파일 이름
                file_name = f"{pbacNo}_{cmdtLnNo}_{currentIndex}.gif"

                try:
                    # 응답 바디(바이너리 데이터) 가져오기
                    image_buffer = response.body()
                    
                    # 파일 생성
                    file_path = os.path.join(TMP_PATH, file_name)

                    # 이미지 파일 저장
                    with open(file_path, "wb") as f:
                        f.write(image_buffer)
                    
                    print(f"저장 완료: {file_name}")
                except Exception as e:
                    print(f"이미지 저장 실패 ({file_name}): {e}")
                finally:
                    downloadCount -= 1

        # 리스너 등록
        page.on("response", handle_response)

        page.goto("https://unipass.customs.go.kr/csp/index.do")
        page.evaluate("myc_f_createLeftMenuLst('MYC_MNU_00000634', 'Y')")
        page.wait_for_timeout(3000)
        # print("초기 메뉴 로드 완료")


        # 물품구분 확인
        # 1: 수입화물(사업자) 2: 휴대품(사업자/개인)
        isBusiness = cmdtNm_value.split("-")[4]

        # 휴대품으로 목록 조회
        if isBusiness == "2":
            page.locator('#MYC0202002Q_cmdtTpcd2').check();
            page.wait_for_timeout(1000)
            page.locator(".search footer button[type='submit']:has-text('조회')").nth(0).click()
            page.wait_for_timeout(3000)

        pages_count = 0
        page_found = False
        while True:

            # 페이지 목록 파악
            page.wait_for_timeout(1000)
            page_lists = page.locator(".paging .pages li")
            total_pages = page_lists.count()
            
            # 목록 페이지를 순회하며 공매 번호 찾기 
            for index in range(1, total_pages + 1):
                cell = page.locator("td[name='pbacNo']", has_text=cmdtNm_value)
                target_row = cell.locator("xpath=ancestor::tr")
                
                if target_row.count() > 0:
                    # print(f"찾았습니다: {cmdtNm_value}.")
                    target_row.locator("a[name='cmdtNm']").first.click()

                    page.wait_for_load_state("networkidle", timeout=30000)
                    page_found = True
                    break

                else:
                    # print(f"{pages_count + index} 페이지에 {cmdtNm_value} 물품이 없습니다. 다음 페이지로 이동합니다.")
                    if index == total_pages:
                        break
                    else:
                        page_lists.nth(index).click()

                page.wait_for_timeout(1000)

            if page_found:
                break

            if page.locator(".paging .next").count() > 0:
                page.locator(".paging .next").click()
                page.wait_for_load_state("networkidle")
                pages_count += 10
            else:
                print("찾는 물건이 존재하지 않습니다.")
                return

        def download_check():
            nonlocal downloadCount
            while downloadCount > 0:
                print(f"다운로드 대기 중... 남은 다운로드: {downloadCount}")
                page.wait_for_timeout(500)

        # 공매 물품 목록 cmdtLnNo 순회
        page.wait_for_timeout(15000)        # 이미지 많을 시 로딩 오래걸림, 실사용은 더 늘려도 될듯
        cmdt_lists = page.locator("#MYC0202003Q_table2 tbody tr")
        cmdt_counts = cmdt_lists.count()
        download_check()
        
        page.wait_for_timeout(3000)

        for count in range(1, cmdt_counts):
            print(f"[{count + 1}/{cmdt_counts}] 번째 세부 물품 클릭...")
            cmdtLnNo += 1
            imageCount = 0

            cmdt_lists.nth(count).locator("td").nth(1).locator("a").click(force=True)

            page.wait_for_timeout(3000)
            try:
                page.wait_for_load_state("networkidle", timeout=30000)
            except Exception as e:
                pass

            download_check()

        print("다운로드가 완료되었습니다. 종료합니다.")
        browser.close()

if __name__ == "__main__":
    main()
