import argparse
import json
import os
from pathlib import Path

from playwright.sync_api import sync_playwright

HEADLESS = True


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


def normalize_cmdt_ln_no(value: str) -> str:
    value = (value or "").strip()
    digits = "".join(ch for ch in value if ch.isdigit())
    if not digits:
        return "0"
    return str(int(digits))


def sanitize_pbac_no(pbac_no: str) -> str:
    return pbac_no.replace("/", "_").replace("\\", "_").strip()




def pbac_digits(pbac_no: str) -> str:
    return "".join(ch for ch in str(pbac_no) if ch.isdigit())


def pbac_hyphenated(pbac_no: str) -> str:
    digits = pbac_digits(pbac_no)
    if len(digits) == 14:
        return f"{digits[:3]}-{digits[3:5]}-{digits[5:7]}-{digits[7:13]}-{digits[13:14]}"
    return pbac_no


def read_pbac_nos_from_file(path: str) -> list[str]:
    p = Path(path)
    if not p.exists():
        return []

    if p.suffix.lower() == ".json":
        data = json.loads(p.read_text(encoding="utf-8"))
        if isinstance(data, list):
            out: list[str] = []
            for row in data:
                if isinstance(row, dict):
                    pbac_no = str(row.get("pbacNo", "")).strip()
                    if pbac_no:
                        out.append(pbac_no)
                elif isinstance(row, str) and row.strip():
                    out.append(row.strip())
            return list(dict.fromkeys(out))

    out: list[str] = []
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            out.append(line)
    return list(dict.fromkeys(out))


def default_pbac_nos() -> list[str]:
    out: list[str] = []
    for filename in ("unipass_all_2b.json", "unipass_all_2c.json"):
        if Path(filename).exists():
            out.extend(read_pbac_nos_from_file(filename))
    return list(dict.fromkeys(out))




def find_target_row(page, pbac_no: str):
    target_digits = pbac_digits(pbac_no)
    rows = page.locator("#MYC0202002Q_table1 tbody tr")
    row_count = rows.count()
    for i in range(row_count):
        row = rows.nth(i)
        td = row.locator("td[name='pbacNo']")
        if td.count() == 0:
            continue
        text = td.first.inner_text().strip()
        if pbac_digits(text) == target_digits:
            return row
    return None


def collect_one(page, pbac_no: str, base_output_dir: str) -> bool:
    target_output = os.path.join(base_output_dir, sanitize_pbac_no(pbac_no))
    os.makedirs(target_output, exist_ok=True)

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
                file_path = os.path.join(target_output, file_name)
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
    page.wait_for_timeout(3000)

    digits = pbac_digits(pbac_no)
    parts = pbac_no.split("-")
    is_business = parts[4] if len(parts) >= 5 else (digits[-1] if len(digits) == 14 else "1")
    if is_business == "2":
        page.locator('#MYC0202002Q_cmdtTpcd2').check()
        page.wait_for_timeout(1000)
        page.locator(".search footer button[type='submit']:has-text('조회')").nth(0).click()
        page.wait_for_timeout(3000)

    page_found = False
    while True:
        page.wait_for_timeout(1000)
        page_lists = page.locator(".paging .pages li")
        total_pages = page_lists.count()

        for index in range(1, total_pages + 1):
            target_row = find_target_row(page, pbac_no)

            if target_row is not None:
                target_row.locator("a[name='cmdtNm']").first.click()
                page.wait_for_load_state("networkidle", timeout=30000)
                page_found = True
                break

            if index != total_pages:
                page_lists.nth(index).click()
                page.wait_for_timeout(1000)

        if page_found:
            break

        if page.locator(".paging .next").count() > 0:
            page.locator(".paging .next").click()
            page.wait_for_load_state("networkidle")
        else:
            print(f"[{pbac_no}] 찾는 물건이 존재하지 않습니다.")
            page.remove_listener("response", handle_response)
            return False

    def download_check():
        nonlocal download_count
        while download_count > 0:
            page.wait_for_timeout(500)

    page.wait_for_timeout(15000)
    cmdt_lists = page.locator("#MYC0202003Q_table2 tbody tr")
    cmdt_counts = cmdt_lists.count()
    download_check()
    page.wait_for_timeout(2000)

    for row_idx in range(cmdt_counts):
        row = cmdt_lists.nth(row_idx)
        row_cmdt_text = row.locator("td").first.inner_text().strip()
        cmdt_ln_no = normalize_cmdt_ln_no(row_cmdt_text)
        image_count = 0

        if row_idx > 0:
            row.locator("td").nth(1).locator("a").click(force=True)
            page.wait_for_timeout(3000)
            try:
                page.wait_for_load_state("networkidle", timeout=30000)
            except Exception:
                pass

        download_check()

    page.remove_listener("response", handle_response)
    print(f"[{pbac_no}] 다운로드 완료")
    return True


def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    if args.pbac_no:
        pbac_nos = [args.pbac_no.strip()]
    elif args.pbac_list_file:
        pbac_nos = read_pbac_nos_from_file(args.pbac_list_file)
    else:
        pbac_nos = default_pbac_nos()

    if not pbac_nos:
        raise ValueError("처리할 공매번호가 없습니다. --pbac-no 또는 --pbac-list-file(혹은 기본 JSON 파일)를 확인하세요.")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not args.headful and HEADLESS)
        ok = 0
        for i, pbac_no in enumerate(pbac_nos, start=1):
            page = browser.new_page()
            print(f"[{i}/{len(pbac_nos)}] 수집 시작: {pbac_no} ({pbac_hyphenated(pbac_no)})")
            if collect_one(page, pbac_no, args.output_dir):
                ok += 1
            page.close()

        browser.close()

    print(f"완료: {ok}/{len(pbac_nos)} 건 성공")


if __name__ == "__main__":
    main()
