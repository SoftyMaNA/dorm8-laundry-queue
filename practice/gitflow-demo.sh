#!/bin/sh
set -eu
target=${1:-../laundry-git-practice}
if [ -e "$target" ]; then
    echo 'Выберите новую папку: указанная уже существует.' >&2
    exit 2
fi
mkdir -p "$target"
cd "$target"
git init -q -b main
git config user.name SoftyMaNA
git config user.email 186196373+SoftyMaNA@users.noreply.github.com
printf '%s\n' 'Прачечная открыта с 08:00 до 22:00.' > rules.txt
git add rules.txt
git commit -m 'docs: записать режим работы прачечной'
git switch -c develop
git switch -c feature/booking-rules
printf '%s\n' 'Пересекающиеся бронирования одной машины запрещены.' >> rules.txt
git add rules.txt
git commit -m 'feat: добавить правило проверки пересечений'
git switch develop
git merge --no-ff feature/booking-rules -m 'Merge feature/booking-rules into develop'
git switch -c release/1.0.0
printf '%s\n' '1.0.0' > VERSION
git add VERSION
git commit -m 'release: подготовить версию 1.0.0'
git switch main
git merge --no-ff release/1.0.0 -m 'Merge release/1.0.0 into main'
git tag -a v1.0.0 -m 'Правила записи в прачечную 1.0.0'
git switch develop
git merge --no-ff release/1.0.0 -m 'Merge release/1.0.0 into develop'
git switch main
git switch -c hotfix/1.0.1
printf '%s\n' 'Соседние интервалы без общего времени не считаются пересечением.' >> rules.txt
printf '%s\n' '1.0.1' > VERSION
git add rules.txt VERSION
git commit -m 'fix: уточнить правило для соседних интервалов'
git switch main
git merge --no-ff hotfix/1.0.1 -m 'Merge hotfix/1.0.1 into main'
git tag -a v1.0.1 -m 'Правила записи в прачечную 1.0.1'
git switch develop
git merge --no-ff hotfix/1.0.1 -m 'Merge hotfix/1.0.1 into develop'
git status --short
git log --graph --decorate --oneline --all
git tag
