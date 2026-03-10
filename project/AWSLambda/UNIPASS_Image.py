import json
import os
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

# 저장 루트
TMP_PATH = "./downloaded_images/"

def parse_args():
    parser = argparse.ArgumentParser(description="UNIPASS 상세 페이지 이미지(.gif) 수집")
    parser.add_argument("--pbac-no", help="조회할 단일 공매번호 (예: 020-26-01-900003-1)")
    parser.add_argument(
        "--pbac-list-file",
        help="공매번호 목록 파일(txt/json). 미지정 시 unipass_all_2b.json+unipass_all_2c.json에서 자동 수집",
    )
    parser.add_argument("--output-dir", default="./downloaded_images", help="이미지 저장 루트 폴더")
    parser.add_argument("--headful", action="store_true", help="브라우저 UI 표시")
    return parser.parse_args()


def digits_only(value: str) -> str:
    return "".join(ch for ch in str(value) if ch.isdigit())


def to_hyphen_pbac_no(pbac_no: str) -> str:
    """
    공매번호 하이픈 포맷 보정
    예) 02026019000031 -> 020-26-01-900003-1
    """
    digits = digits_only(pbac_no)
    if len(digits) == 14:
        return f"{digits[:3]}-{digits[3:5]}-{digits[5:7]}-{digits[7:13]}-{digits[13]}"
    return str(pbac_no).strip()


def load_pbac_nos() -> list[str]:
    """
    미리 수집한 목록 JSON(unipass_all_2b.json / unipass_all_2c.json)에서
    pbacNo를 읽고, 중복 제거 후 반환
    """
    pbac_nos: list[str] = []
    for filename in ("unipass_all_2b.json", "unipass_all_2c.json"):
        path = Path(filename)
        if not path.exists():
            continue

        with path.open("r", encoding="utf-8") as f:
            rows = json.load(f)

        if not isinstance(rows, list):
            continue

        for row in rows:
            if not isinstance(row, dict):
                continue
            pbac_no = str(row.get("pbacNo", "")).strip()
            if pbac_no:
                pbac_nos.append(pbac_no)

    # digits 기준 중복 제거
    uniq: dict[str, str] = {}
    for pbac_no in pbac_nos:
        key = digits_only(pbac_no)
        if key and key not in uniq:
            uniq[key] = to_hyphen_pbac_no(pbac_no)

    return list(uniq.values())


def find_target_row(page, pbac_no: str):
    target_digits = digits_only(pbac_no)
    rows = page.locator("#MYC0202002Q_table1 tbody tr")
    for i in range(rows.count()):
        row = rows.nth(i)
        cell = row.locator("td[name='pbacNo']")
        if cell.count() == 0:
            continue
        cell_digits = digits_only(cell.first.inner_text().strip())
        if cell_digits == target_digits:
            return row
    return None


def collect_single_pbac(page, pbac_no: str) -> bool:
    save_dir = os.path.join(TMP_PATH, pbac_no)
    os.makedirs(save_dir, exist_ok=True)

    download_count = 0
    cmdt_ln_no = "1"
    image_count = 0

    def handle_response(response):
        nonlocal download_count, cmdt_ln_no, image_count

        url = response.url
        content_type = response.headers.get("content-type", "")

        if "DOC" in url and "image" in content_type:
            download_count += 1
            current_index = image_count
            image_count += 1
            file_name = f"0_{cmdt_ln_no}_{current_index}.gif"

            try:
                image_buffer = response.body()
                file_path = os.path.join(save_dir, file_name)
                with open(file_path, "wb") as f:
                    f.write(image_buffer)
                print(f"[{pbac_no}] 저장 완료: {file_name}")
            except Exception as e:
                print(f"[{pbac_no}] 이미지 저장 실패 ({file_name}): {e}")
            finally:
                download_count -= 1

    page.on("response", handle_response)

    page.goto("https://unipass.customs.go.kr/csp/index.do")
    page.evaluate("myc_f_createLeftMenuLst('MYC_MNU_00000634', 'Y')")
    time.sleep(3)

    # 물품구분 확인
    # 1: 수입화물(사업자) 2: 휴대품(사업자/개인)
    is_business = pbac_no.split("-")[4]

    if is_business == "2":
        page.locator('#MYC0202002Q_cmdtTpcd2').check()
        time.sleep(1)
        page.locator(".search footer button[type='submit']:has-text('조회')").nth(0).click()
        time.sleep(3)

    found = False
    pages_count = 0
    while True:
        time.sleep(1)
        page_lists = page.locator(".paging .pages li")
        total_pages = page_lists.count()

        for index in range(1, total_pages + 1):
            target_row = find_target_row(page, pbac_no)

            if target_row is not None:
                target_row.locator("a[name='cmdtNm']").first.click()
                try:
                    page.wait_for_load_state("networkidle", timeout=30000)
                except Exception:
                    pass
                found = True
                break

            if index != total_pages:
                page_lists.nth(index).click()
                time.sleep(1)

        if found:
            break

        if page.locator(".paging .next").count() > 0:
            page.locator(".paging .next").click()
            page.wait_for_load_state("networkidle")
            pages_count += 10
        else:
            print(f"[{pbac_no}] 찾는 물건이 존재하지 않습니다.")
            page.remove_listener("response", handle_response)
            return False

    # 첫 항목 로딩 대기
    time.sleep(15)

    def wait_downloads():
        nonlocal download_count
        while download_count > 0:
            page.wait_for_timeout(500)

    cmdt_lists = page.locator("#MYC0202003Q_table2 tbody tr")
    cmdt_count = cmdt_lists.count()
    wait_downloads()
    time.sleep(2)

    # 상세 항목 순회
    for row_idx in range(cmdt_count):
        row = cmdt_lists.nth(row_idx)
        row_no = row.locator("td").first.inner_text().strip()
        cmdt_ln_no = str(int("".join(ch for ch in row_no if ch.isdigit()) or "0"))
        image_count = 0

        if row_idx > 0:
            row.locator("td").nth(1).locator("a").click(force=True)
            time.sleep(3)
            try:
                page.wait_for_load_state("networkidle", timeout=30000)
            except Exception:
                pass

        wait_downloads()

    page.remove_listener("response", handle_response)
    print(f"[{pbac_no}] 다운로드 완료")
    return True


def main():
    os.makedirs(TMP_PATH, exist_ok=True)

    pbac_nos = load_pbac_nos()
    if not pbac_nos:
        raise FileNotFoundError("unipass_all_2b.json / unipass_all_2c.json 에서 공매번호를 찾지 못했습니다.")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)

        ok = 0
        for i, raw_pbac_no in enumerate(pbac_nos, start=1):
            pbac_no = to_hyphen_pbac_no(raw_pbac_no)
            page = browser.new_page()
            print(f"[{i}/{len(pbac_nos)}] 수집 시작: {pbac_no}")
            if collect_single_pbac(page, pbac_no):
                ok += 1
            page.close()

        browser.close()

    print(f"완료: {ok}/{len(pbac_nos)} 건 성공")


    print(f"완료: {ok}/{len(pbac_nos)} 건 성공")


if __name__ == "__main__":
    main()
