#!/bin/sh
# Demo data: a folder of small generated media and awkward names, nothing real, for running
# indexof locally (CONTRIBUTING › Run it on demo data), screenshots and the integration test.
#   sh tests/make-demo.sh demo
# Makes, under the folder given (created if needed; re-running on an existing one is fine):
#   movies/    Big Buck Test (2024)/Big Buck Test (2024).mkv: 30 s of H.264 with two audio
#              tracks (E-AC3 5.1 "Français 5.1" fre, the default, and AAC stereo "English" eng)
#              and two subtitle tracks (fre, eng), a keyframe every 2 s; Short (2023).mp4: 15 s
#              of H.264 + AAC, with a subtitle file next to it, Short (2023).fr.srt; Long Take
#              (2022).mp4: 2:30 at 192x108, for the player's "resumed at" (it needs more than
#              1:30); Amélie (2001)/L'Amour & #1?.mkv, a copy of the first (every track behind a
#              name with an apostrophe, an ampersand, a hash and a question mark)
#   music/     an .mp3 and a .flac, 10 s tones with tags
#   pictures/  a .png and a .jpg
#   share/     (meant to be mounted writable) notes.txt, link-to-passwd -> /etc/passwd, a folder
#              whose name ends with a line break holding etc/passwd (dummy text), files named
#              -TT=x, * and 100% done.txt, and many/ with 1,500 empty files
#   documents/ (meant to be mounted writable; the README's listing screenshot) one file of each
#              main kind: a video, a song, a picture, a GIF, a PDF, notes, a zip, a disk image
#              (a kind with no preview) and a folder of photos
# ffmpeg runs in the helper image (indexof-helper:test built by the integration test, or the
# published ghcr.io/lborruto/indexof-helper:main, or INDEXOF_HELPER_IMAGE) as the invoking user
# with the folder bind-mounted, so nothing needs installing; without a helper image it uses the
# machine's ffmpeg, and pulls the published image when there is neither.
set -eu

[ $# -eq 1 ] || { echo 'usage: sh tests/make-demo.sh <dir>' >&2; exit 2; }
mkdir -p -- "$1"
dir=$(cd -- "$1" && pwd -P)
cd -- "$dir"

# ffmpeg: a helper image already here, else the machine's ffmpeg, else the published image.
image=
for i in ${INDEXOF_HELPER_IMAGE:-} indexof-helper:test ghcr.io/lborruto/indexof-helper:main; do
  if docker image inspect "$i" >/dev/null 2>&1; then image=$i; break; fi
done
if [ -z "$image" ] && ! command -v ffmpeg >/dev/null 2>&1; then
  image=ghcr.io/lborruto/indexof-helper:main
  command -v docker >/dev/null 2>&1 && echo "make-demo: no helper image and no ffmpeg here, pulling $image" >&2
  if ! command -v docker >/dev/null 2>&1 || ! docker pull -q "$image" >/dev/null; then
    echo 'make-demo: needs ffmpeg: build the helper image (sh tests/integration.sh, or docker compose build), install ffmpeg, or pull ghcr.io/lborruto/indexof-helper:main' >&2
    exit 1
  fi
fi
uid=$(id -u); gid=$(id -g)
ff() {
  if [ -n "$image" ]; then
    docker run --rm --network none --user "$uid:$gid" -v "$dir:/demo" -w /demo --entrypoint ffmpeg "$image" -hide_banner -loglevel error -nostdin -y "$@"
  else
    ffmpeg -hide_banner -loglevel error -nostdin -y "$@"
  fi
}

# The subtitles to embed, written in a scratch folder inside the demo folder (the container
# sees nothing else), removed at the end.
scratch=.make-demo
trap 'rm -rf "$dir/$scratch"' EXIT
mkdir -p "$scratch" 'movies/Big Buck Test (2024)' 'movies/Amélie (2001)' music pictures share/many 'documents/Holiday photos'
cat >"$scratch/fre.srt" <<'EOF'
1
00:00:01,000 --> 00:00:04,000
Bonjour ! Ceci est une démo.

2
00:00:05,000 --> 00:00:09,000
Les sous-titres sont dans le fichier.

3
00:00:10,000 --> 00:00:14,000
<i>Deux pistes audio : français et anglais.</i>

4
00:00:20,000 --> 00:00:24,000
Fin de la démo.
EOF
cat >"$scratch/eng.srt" <<'EOF'
1
00:00:01,000 --> 00:00:04,000
Hello! This is a demo.

2
00:00:05,000 --> 00:00:09,000
The subtitles are inside the file.

3
00:00:10,000 --> 00:00:14,000
<i>Two audio tracks: French and English.</i>

4
00:00:20,000 --> 00:00:24,000
End of the demo.
EOF

# movies: the feature (test pattern, two tones with beeps so the tracks can be told apart, a
# keyframe every 2 s = 50 frames at 25 fps), the short, the odd name.
ff -f lavfi -i testsrc=size=640x360:rate=25 \
  -f lavfi -i sine=frequency=440:beep_factor=4:sample_rate=48000 \
  -f lavfi -i sine=frequency=660:beep_factor=2:sample_rate=48000 \
  -i "$scratch/fre.srt" -i "$scratch/eng.srt" -t 30 \
  -map 0:v -map 1:a -map 2:a -map 3:s -map 4:s \
  -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p -g 50 -keyint_min 50 -sc_threshold 0 \
  -filter:a:0 aformat=channel_layouts=5.1 -c:a:0 eac3 -b:a:0 192k \
  -filter:a:1 aformat=channel_layouts=stereo -c:a:1 aac -b:a:1 96k \
  -c:s copy -metadata title='Big Buck Test' -disposition:v:0 default \
  -metadata:s:a:0 language=fre -metadata:s:a:0 title='Français 5.1' -disposition:a:0 default \
  -metadata:s:a:1 language=eng -metadata:s:a:1 title=English -disposition:a:1 0 \
  -metadata:s:s:0 language=fre -metadata:s:s:0 title=Français -disposition:s:0 0 \
  -metadata:s:s:1 language=eng -metadata:s:s:1 title=English -disposition:s:1 0 \
  'movies/Big Buck Test (2024)/Big Buck Test (2024).mkv'
ff -f lavfi -i testsrc2=size=640x360:rate=25 \
  -f lavfi -i sine=frequency=330:beep_factor=3:sample_rate=48000 -t 15 \
  -map 0:v -map 1:a \
  -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p -g 50 -keyint_min 50 -sc_threshold 0 \
  -filter:a aformat=channel_layouts=stereo -c:a aac -b:a 96k -metadata:s:a:0 language=eng \
  -metadata title=Short -movflags +faststart \
  'movies/Short (2023).mp4'
# (long enough to be resumed: kept from 30 s in to a minute before the end; tiny, about 1 MB)
ff -f lavfi -i testsrc=size=192x108:rate=10 \
  -f lavfi -i sine=frequency=550:beep_factor=4:sample_rate=22050 -t 150 \
  -map 0:v -map 1:a \
  -c:v libx264 -preset veryfast -crf 35 -pix_fmt yuv420p -g 20 \
  -c:a aac -ac 1 -b:a 32k -metadata title='Long Take' -movflags +faststart \
  'movies/Long Take (2022).mp4'
cp -f 'movies/Big Buck Test (2024)/Big Buck Test (2024).mkv' "movies/Amélie (2001)/L'Amour & #1?.mkv"
# (a subtitle file next to the short, for the player's "fr (file)")
cat >'movies/Short (2023).fr.srt' <<'EOF'
1
00:00:01,000 --> 00:00:04,000
Un fichier de sous-titres à côté de la vidéo.

2
00:00:06,000 --> 00:00:10,000
Il porte son nom, plus la langue : .fr.srt
EOF

# music: 10 s tones, tagged.
ff -f lavfi -i sine=frequency=440:beep_factor=2:sample_rate=44100 -t 10 \
  -filter:a aformat=channel_layouts=stereo -c:a libmp3lame -b:a 128k -id3v2_version 3 \
  -metadata title='Demo Song' -metadata artist=Nobody -metadata album='Test Tones' \
  -metadata date=2024 -metadata track=1 -metadata genre=Demo \
  'music/Demo Song.mp3'
ff -f lavfi -i sine=frequency=880:beep_factor=2:sample_rate=44100 -t 10 \
  -filter:a aformat=channel_layouts=stereo -c:a flac -sample_fmt s16 \
  -metadata title='Démo (lossless)' -metadata artist=Nobody -metadata album='Test Tones' \
  -metadata date=2024 -metadata track=2 -metadata genre=Demo \
  'music/Démo (lossless).flac'

# pictures: one frame each.
ff -f lavfi -i testsrc2=size=1280x720 -frames:v 1 'pictures/Test Pattern.png'
ff -f lavfi -i gradients=size=1280x720:seed=7 -frames:v 1 -q:v 4 -pix_fmt yuvj420p 'pictures/Gradient (2024).jpg'

# share: plain notes, then the awkward entries (a symbolic link out of the folder, a name
# ending with a line break, a name that looks like an option, a shell pattern, a percent sign)
# and a folder of 1,500 entries.
cat >share/notes.txt <<'EOF'
Demo data made by tests/make-demo.sh: nothing here is real.
This folder is meant to be mounted writable, so uploads, renames and deletions can be tried.
EOF
ln -sfn /etc/passwd share/link-to-passwd
nl=$(printf '\nx'); nl=${nl%x}
mkdir -p "share/a$nl/etc"
echo 'Not a real passwd file: a folder whose name ends with a line break, holding etc/passwd.' >"share/a$nl/etc/passwd"
: >'share/-TT=x'
: >'share/*'
echo 'A name with a percent sign.' >'share/100% done.txt'
awk 'BEGIN { for (i = 1; i <= 1500; i++) printf "share/many/file-%04d.txt\n", i }' | xargs touch

# documents: one of each main kind, for the listing's links ([download] [raw] [vlc], the name
# opening the viewer, the browser's PDF reader, or downloading).
ff -i 'movies/Short (2023).mp4' -c copy 'documents/Holiday clip.mkv'
cp -f 'music/Demo Song.mp3' 'documents/Song.mp3'
cp -f 'pictures/Gradient (2024).jpg' 'documents/Sunset.jpg'
cp -f 'pictures/Test Pattern.png' 'documents/Holiday photos/Beach.png'
ff -f lavfi -i testsrc2=size=160x90:rate=10 -t 2 'documents/Spinner.gif'
cat >'documents/Notes.txt' <<'EOF'
Demo data made by tests/make-demo.sh: nothing here is real.
Shopping: bread, coffee, batteries.
EOF
# (A one-page PDF, written as it is: the offsets in its xref table count these exact bytes.)
cat >'documents/Report.pdf' <<'EOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 50 >>
stream
BT /F1 24 Tf 72 760 Td (indexof demo: a PDF) Tj ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000241 00000 n 
0000000341 00000 n 
trailer
<< /Size 6 /Root 1 0 R >>
startxref
411
%%EOF
EOF
# (The notes and the photos zipped, by the helper image's zip or this machine's; with neither, an
# empty zip: its end-of-directory record alone, 22 bytes.)
rm -f documents/Archive.zip
if [ -n "$image" ]; then
  docker run --rm --network none --user "$uid:$gid" -v "$dir:/demo" -w /demo/documents --entrypoint zip "$image" -q -r Archive.zip Notes.txt 'Holiday photos'
elif command -v zip >/dev/null 2>&1; then
  (cd documents && zip -q -r Archive.zip Notes.txt 'Holiday photos')
else
  printf 'PK\005\006\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' >documents/Archive.zip
fi
dd if=/dev/zero of='documents/Installer.iso' bs=1024 count=2048 2>/dev/null

rm -rf "$scratch"
many=$(find share/many -type f | wc -l | tr -d ' ')
echo "make-demo: $dir: movies (4, 1 subtitle file), music (2), pictures (2), share (5 files, 1 symbolic link, many/ with $many files), documents (8 files, 1 folder); ffmpeg from ${image:-this machine}"
