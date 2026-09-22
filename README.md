# imac-setup

macOS 키보드 실습 환경 자동 설정 스크립트. 사용 방법은 https://newids.github.io/imac-setup 을 보세요.

```sh
curl -fsSL https://newids.github.io/imac-setup/iMac-setup.sh | sh -s -- han3final
```

## 구성

- `iMac-setup.sh`: 스크립트 본체. 원본은 codyssey-imac 저장소(옛 claude-docker)에서 관리하고 여기에 동기화한다.
- `iMac4newids.sh`: 개인용. `iMac-setup.sh` 와 codyssey-imac 의 `setup.sh` 를 합친 것으로, 두벌식 없이
  세벌식 최종만 넣고 핫 코너, zsh 프롬프트, ssh 키, git 설정, Discord 업데이트 건너뛰기, Terminal 프로파일,
  Claude Code 설치까지 한다.
  원본은 역시 codyssey-imac 에 있다.

  ```sh
  curl -fsSL https://newids.github.io/imac-setup/iMac4newids.sh | sh
  ```

  ssh 키는 같은 자리의 `keys.zip.enc`(codyssey-imac 의 `encrypt.sh` 로 `keys.zip` 을 암호화한 것)를 받아
  실행 중에 암호를 묻고 푼다. 파일이 없으면 그 단계만 건너뛴다. 암호화하지 않은 키는 올리지 않는다.
- `index.html`, `assets/`: GitHub Pages 안내 페이지. Jekyll 없이 정적 파일로 배포한다 (`.nojekyll`).
  로컬 확인: `python3 -m http.server 8765` 후 http://localhost:8765/
