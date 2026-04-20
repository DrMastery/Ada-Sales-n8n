#!/bin/bash

# --- НАСТРОЙКИ ---
CONTAINER_NAME="root-n8n-worker-1"
BACKUP_NAME="active_$(date +'%Y-%m-%d_%H-%M')"
INTERNAL_DIR="/tmp/n8n_export"
TEMP_LOCAL="./temp_raw"

echo "🚀 Запуск экспорта ТОЛЬКО активных воркфлоу..."

# 1. Очистка временных папок
docker exec -u node $CONTAINER_NAME rm -rf $INTERNAL_DIR
docker exec -u node $CONTAINER_NAME mkdir -p $INTERNAL_DIR
rm -rf "$TEMP_LOCAL"
mkdir -p "$TEMP_LOCAL"

# 2. Экспорт всех воркфлоу во временную папку контейнера
docker exec -u node $CONTAINER_NAME n8n export:workflow --all --backup --output=$INTERNAL_DIR/

# 3. Перенос файлов из контейнера на сервер (через поток tar)
docker exec -u node $CONTAINER_NAME sh -c "cd $INTERNAL_DIR && tar -cf - ." | tar -xf - -C "$TEMP_LOCAL/"

# 4. Создание папки для этого бэкапа
mkdir -p "./$BACKUP_NAME"

# 5. ФИЛЬТРАЦИЯ: Оставляем только те, где "active": true
ACTIVE_COUNT=0
for file in $(find "$TEMP_LOCAL" -name "*.json"); do
    if [ "$(jq '.active' "$file" 2>/dev/null)" == "true" ]; then
        cp "$file" "./$BACKUP_NAME/"
        ACTIVE_COUNT=$((ACTIVE_COUNT+1))
    fi
done

# 6. Удаление временного мусора
rm -rf "$TEMP_LOCAL"
docker exec -u node $CONTAINER_NAME rm -rf $INTERNAL_DIR

# 7. Отправка в GitHub
if [ "$ACTIVE_COUNT" -gt 0 ]; then
    echo "✅ Сохранено активных сценариев: $ACTIVE_COUNT"
    git add .
    git commit -m "Backup: $BACKUP_NAME ($ACTIVE_COUNT active workflows)"
    git push origin main
    echo "🏁 Синхронизировано с GitHub."
else
    echo "⚠️ Активных сценариев не найдено. Проверь статус в n8n."
    rm -rf "./$BACKUP_NAME"
fi
