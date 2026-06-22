# privacy-pages

全アプリのプライバシーポリシーをGitHub Pagesでホストするリポジトリ。

## 公開URL（設定後）

- FocusLock: https://j2tcr4xfhn-ux.github.io/privacy/focuslock/
- めんせつAI: https://j2tcr4xfhn-ux.github.io/privacy/mensetsuai/
- InvoiceKit: https://j2tcr4xfhn-ux.github.io/privacy/invoicekit/
- CoupleWallet: https://j2tcr4xfhn-ux.github.io/privacy/couplewallet/

## GitHub Pages 有効化手順（5分）

1. GitHubで `privacy` という名前のリポジトリを新規作成（Public）
2. このフォルダをpush:
   ```bash
   cd ~/Projects/privacy-pages
   git init
   git add .
   git commit -m "Add privacy policies"
   git remote add origin https://github.com/oshimiren/privacy.git
   git push -u origin main
   ```
3. GitHubリポジトリの Settings → Pages → Source: Deploy from branch → main → / (root) → Save
4. 数分後に https://j2tcr4xfhn-ux.github.io/privacy/ でアクセス可能になる
