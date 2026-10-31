#!/bin/sh
# Demo data: a folder of small generated media and awkward names, nothing real, for running
# indexof locally (CONTRIBUTING › Run it on demo data), screenshots and the integration test.
#   sh tests/make-demo.sh demo
# Makes, under the folder given (created if needed; re-running on an existing one is fine):
#   movies/    Big Buck Test (2024)/Big Buck Test (2024).mkv: 30 s of H.264 with two audio
#              tracks (E-AC3 5.1 "Français 5.1" fre, the default, and AAC stereo "English" eng)
#              and two subtitle tracks (fre, eng), a keyframe every 2 s; Short (2023).mp4: 15 s
#              of H.264 + AAC; Amélie (2001)/L'Amour & #1?.mkv, a copy of the first (every
#              track behind a name with an apostrophe, an ampersand, a hash and a question mark)
#   music/     an .mp3 and a .flac, 10 s tones with tags
#   pictures/  a .png and a .jpg
#   share/     (meant to be mounted writable) notes.txt, link-to-passwd -> /etc/passwd, a folder
#              whose name ends with a line break holding etc/passwd (dummy text), files named
#              -TT=x, * and 100% done.txt, and many/ with 1,500 empty files
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
mkdir -p "$scratch" 'movies/Big Buck Test (2024)' 'movies/Amélie (2001)' music pictures share/many
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
cp -f 'movies/Big Buck Test (2024)/Big Buck Test (2024).mkv' "movies/Amélie (2001)/L'Amour & #1?.mkv"

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

rm -rf "$scratch"
many=$(find share/many -type f | wc -l | tr -d ' ')
echo "make-demo: $dir: movies (3), music (2), pictures (2), share (5 files, 1 symbolic link, many/ with $many files); ffmpeg from ${image:-this machine}"
