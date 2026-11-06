#!/usr/bin/env bash
# Build the Flutter web app and deploy build/web to Vercel.
#
#   bash tool/deploy_web.sh          # preview deployment
#   bash tool/deploy_web.sh --prod   # production deployment
#
# Vercel must receive the *build output*, not web/. web/ is only the template
# Flutter copies from; it has no flutter_bootstrap.js, main.dart.js or assets/,
# and web/vercel.json rewrites every missing path to index.html — so deploying
# web/ yields "Expected a JavaScript module ... MIME type text/html".
#
# The project link lives in .vercel/ at the app root (gitignored). flutter
# build web wipes build/web, so the link is copied in after every build.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .vercel/project.json ]; then
  echo "No .vercel/project.json. Run 'vercel link' in $(pwd) first." >&2
  exit 1
fi
if [ ! -f .env ]; then
  echo "No .env. Copy .env.example to .env and fill in the Supabase values." >&2
  exit 1
fi

flutter build web --release --dart-define-from-file=.env

rm -rf build/web/.vercel
cp -r .vercel build/web/.vercel

vercel deploy --cwd build/web --yes "$@"
