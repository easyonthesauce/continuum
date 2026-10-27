# CONTINUUM

A webcam frame becomes the next few seconds of video, via MiniMax H3 image-to-video on the Venice API.

Pick a mode (Boring / Luck / Murphy's Law / Funny / Serious / Custom), optionally arm the 18+ layer,
shoot. Each shot is queued first-come-first-served, directed by a vision model, rendered, and saved
with a name that describes the scene.

## Windows

    winget install OpenJS.NodeJS
    $env:VENICE_API_KEY="sk-..."; node server.mjs
    # open http://localhost:8787

For the camera on a phone, either use a tunnel (real cert, no trust setup):

    winget install Cloudflare.cloudflared
    cloudflared tunnel --url http://localhost:8787

or a trusted local cert with mkcert:

    winget install FiloSottile.mkcert
    mkcert -install
    mkcert localhost 127.0.0.1 <your-lan-ip>
    Copy-Item (Join-Path (mkcert -CAROOT) "rootCA.pem") .
    $env:TLS_KEY="localhost+2-key.pem"; $env:TLS_CERT="localhost+2.pem"; node server.mjs

Install rootCA.pem on the phone from https://<your-ip>:8787/rootCA.pem, then enable trust in
Settings > General > About > Certificate Trust Settings.

Open the firewall once, as admin:

    New-NetFirewallRule -DisplayName "Continuum 8787" -Direction Inbound -LocalPort 8787 -Protocol TCP -Action Allow

## Deploy to Vercel

    npm i -g vercel
    vercel link
    vercel env add VENICE_API_KEY production
    vercel --prod

## Save ladder

First available wins: desktop folder -> server disk (./captures) -> device storage (OPFS) ->
share sheet -> Downloads. The header badge shows which is live.