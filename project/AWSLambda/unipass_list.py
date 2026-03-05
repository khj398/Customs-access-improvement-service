import json
import os
import re
import time
from typing import Any, Iterable

from playwright.sync_api import sync_playwright

# AWS Lambdda 저장 경로
# TMP_PATH = "/tmp/"
TMP_PATH = "./"

# 설정
HEADLESS = False
KEYWORD = "retrievePbacCmdt.do"
TEMP_FILE_PREFIX = "temp_page_"
FINAL_FILE = "unipass_all.json"

IMAGE_FIELD_HINTS = (
    "img",
    "image",
    "photo",
    "thumb",
    "file",
    "attach",
)
IMAGE_URL_PATTERN = re.compile(r"https?://[^\s\"'<>]+", re.IGNORECASE)


def _flatten_values(value: Any) -> Iterable[Any]:
    if isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from _flatten_values(v)
    elif isinstance(value, list):
        for v in value:
            yield from _flatten_values(v)
    else:
        yield value


def _looks_like_image_url(url: str) -> bool:
    lowered = url.lower()
    if any(hint in lowered for hint in IMAGE_FIELD_HINTS):
        return True
    return lowered.endswith((".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"))


def extract_image_urls(item: dict[str, Any]) -> list[str]:
    found: list[str] = []
    for v in _flatten_values(item):
        if not isinstance(v, str):
            continue

        # JSON 문자열 내부에 URL이 들어있는 경우까지 포함
        candidates = IMAGE_URL_PATTERN.findall(v)
        for candidate in candidates:
            if _looks_like_image_url(candidate):
                found.append(candidate)

        if _looks_like_image_url(v):
            found.append(v)

    # 순서 보존 중복 제거
    deduped = list(dict.fromkeys(found))
    return deduped


# 페이지 응답 JSON 저장
def save_temp_json(response, index):
    try:
        data = response.json()
        items = data.get("items", [])  # items 키의 값 추출 (실제 물품 목록 데이터)

        for item in items:
            item["image_urls"] = extract_image_urls(item)
            item["image_count"] = len(item["image_urls"])

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

    total_images = sum(len(x.get("image_urls", [])) for x in all_data)
    print(f"\n최종 통합 완료: {FINAL_FILE} (총 {len(all_data)}건)")
    print(f"이미지 URL 수집 결과: 총 {total_images}건")


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=HEADLESS)
        page = browser.new_page()

        print("Unipass 접속 및 초기 데이터 수신...")
        page.goto("https://unipass.customs.go.kr/csp/index.do")

        # 1페이지
        with page.expect_response(lambda r: KEYWORD in r.url) as resp:
            page.evaluate("myc_f_createLeftMenuLst('MYC_MNU_00000634', 'Y')")
        save_temp_json(resp.value, 1)

        # 페이지 목록 파악
        time.sleep(1)
        page_lists = page.locator(".paging .pages li")
        total_pages = page_lists.count()

        # 2페이지부터
        for index in range(2, total_pages + 1):
            with page.expect_response(lambda r: KEYWORD in r.url) as resp:
                page_lists.nth(index - 1).click()
            save_temp_json(resp.value, index)
            time.sleep(1)

        browser.close()

        merge_and_cleanup(total_pages if total_pages > 0 else 1)


if __name__ == "__main__":
    main()
