import json
import boto3
import os
from playwright.sync_api import sync_playwright, Error as PlaywrightError

s3 = boto3.client('s3')
BUCKET_NAME = 'cais-playwright-images'

# 공매 번호 하이픈 복구 함수
def restore_hyphens(raw_id):
    raw_str = str(raw_id)
    if not raw_id or len(raw_str) != 14:
        return raw_str # 14자리가 아니면 원본 반환

    return f"{raw_str[:3]}-{raw_str[3:5]}-{raw_str[5:7]}-{raw_str[7:13]}-{raw_str[13:]}"

def handler(event, context):
    records = event.get('Records', [event])

    for record in records:
        if 'body' in record and isinstance(record['body'], str):
            data = json.loads(record['body'])
        else:
            data = record
        
        target_list = data.get('targets')
        
        if not target_list:
            single_target = data.get('target_id', None)
            if single_target is None:
                print("target_id가 입력되지 않았습니다. 작업을 종료합니다.")
                continue 
            target_list = [single_target]

        target_list = sorted(list(set(target_list)))
        
        # 공매 번호 목록을 처리 함수로 전달
        process_targets(target_list)

    return {
        "Result": "Download Success"
    }

def process_targets(target_list):
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu", "--single-process"]
        )
        # 캐시를 무효화, 응답 유실 방지
        context = browser.new_context(
            extra_http_headers={"Cache-Control": "no-cache", "Pragma": "no-cache"}
        )
        page = context.new_page()

        current_formatted_id = ""
        downloadCount = 0
        cmdtLnNo = 1
        imageCount = 0

        def handle_response(response):
            nonlocal downloadCount, cmdtLnNo, imageCount, current_formatted_id
            
            if not current_formatted_id:
                return

            url = response.url
            content_type = response.headers.get("content-type", "")

            if "DOC" in url and "image" in content_type:
                downloadCount += 1
                try:
                    response.finished()
                    
                    currentIndex = imageCount
                    imageCount += 1

                    ext = content_type.split("/")[-1] if "/" in content_type else "gif"
                    file_name = f"{current_formatted_id}_{cmdtLnNo}_{currentIndex}.{ext}"
                    s3_key = f"{current_formatted_id}/{file_name}"

                    image_buffer = response.body()
                    s3.put_object(
                        Bucket=BUCKET_NAME,
                        Key=s3_key,
                        Body=image_buffer,
                        ContentType=content_type
                    )
                    print(f"S3 저장 완료: {s3_key}")
                except Exception as e:
                    print(f"이미지 저장 실패 ({url}): {e}")
                finally:
                    downloadCount -= 1

        page.on("response", handle_response)

        for raw_id in target_list:
            if not raw_id:
                continue
            
            current_formatted_id = restore_hyphens(raw_id)
            print(f"\n--- {current_formatted_id} 작업 시작 ---")
            
            # S3 중복 체크 로직
            try:
                check_resp = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=f"{current_formatted_id}/", MaxKeys=1)
                if 'Contents' in check_resp:
                    print(f"[{current_formatted_id}] 이미 존재하는 이미지므로 건너뜁니다.")
                    continue
            except: pass

            downloadCount = 0
            cmdtLnNo = 1
            imageCount = 0

            page.goto("https://unipass.customs.go.kr/csp/index.do", wait_until="domcontentloaded")
            page.evaluate("myc_f_createLeftMenuLst('MYC_MNU_00000634', 'Y')")
            
            # 특정 요소(휴대품 구분)가 뜰 때까지 대기
            try:
                page.wait_for_selector('#MYC0202002Q_cmdtTpcd2', timeout=10000)
                isBusiness = current_formatted_id.split("-")[4]
                if isBusiness == "2":
                    page.locator('#MYC0202002Q_cmdtTpcd2').check()
                    page.wait_for_timeout(500)
                    page.locator(".search footer button[type='submit']:has-text('조회')").nth(0).click()
                
                # 목록 테이블(02Q)이 나타날 때까지 대기
                page.wait_for_selector("#MYC0202002Q_table tbody tr", state="attached", timeout=10000)
            except:
                print(f"[{current_formatted_id}] 로딩 실패")
                continue

            page_found = False
            while True:
                page.wait_for_timeout(1000)
                page_lists = page.locator(".paging .pages li")
                total_pages = page_lists.count()
                
                for index in range(1, total_pages + 1):
                    # 목록 테이블(02Q) 내에서 정확한 공매번호 행 검색
                    cell = page.locator(f"#MYC0202002Q_table td[name='pbacNo']", has_text=current_formatted_id)
                    
                    if cell.count() > 0:
                        cell.locator("xpath=ancestor::tr").locator("a[name='cmdtNm']").first.click()

                        try:
                            page.wait_for_load_state("networkidle", timeout=10000)
                        except: pass
                        page_found = True
                        break
                    else:
                        if index == total_pages: break
                        page_lists.nth(index).click()
                        # 페이지 이동 후 테이블 갱신 대기
                        page.wait_for_selector("#MYC0202002Q_table tbody tr", state="visible", timeout=5000)
                        page.wait_for_timeout(500)

                if page_found: break
                if page.locator(".paging .next").count() > 0:
                    page.locator(".paging .next").click()
                    page.wait_for_selector("#MYC0202002Q_table tbody tr", state="visible", timeout=10000)
                else: break

            if not page_found:
                print(f"[{current_formatted_id}] 해당 공매 번호는 존재하지 않습니다.")
                continue

            def download_check():
                nonlocal downloadCount
                for _ in range(20): # 최대 10초
                    if downloadCount <= 0:
                        page.wait_for_timeout(500)
                        if downloadCount <= 0: break
                    page.wait_for_timeout(500)

            try:
                page.wait_for_selector("#MYC0202003Q_table2 tbody tr", state="attached", timeout=15000)
            except: pass

            cmdt_lists = page.locator("#MYC0202003Q_table2 tbody tr")
            cmdt_counts = cmdt_lists.count()
            download_check()

            # 세부 물품 루프
            for count in range(1, cmdt_counts):
                print(f"[{count + 1}/{cmdt_counts}] 세부 물품 클릭 중...")
                cmdtLnNo += 1
                imageCount = 0
                cmdt_lists.nth(count).locator("td").nth(1).locator("a").click(force=True)
                page.wait_for_timeout(1000) 
                download_check()

            print(f"[{current_formatted_id}] 완료.")

        try:
            if not page.is_closed():
                page.remove_listener("response", handle_response)
                page.wait_for_timeout(1000)
                page.close()
                
            context.close()
            browser.close()
            print("브라우저 및 세션이 안전하게 종료되었습니다.")
        
        except Exception as e:
            print(f"종료 과정 중 알림 : {e}")

        print("\n전체 작업 완료.")