# imac-setup

macOS 키보드 실습 환경 자동 설정 스크립트. 사용 방법은 https://newids.github.io/imac-setup 을 보세요.

```sh
curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh -s -- han3final
```

## 구성

- `iMac-setup.sh`: 스크립트 본체. 원본은 claude-docker 저장소에서 관리하고 여기에 동기화한다.
- `index.html`, `assets/`: GitHub Pages 안내 페이지. Jekyll 없이 정적 파일로 배포한다 (`.nojekyll`).
  로컬 확인: `python3 -m http.server 8765` 후 http://localhost:8765/
