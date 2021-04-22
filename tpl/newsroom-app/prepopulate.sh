_missing_db() {
    ! { curl -sI "$ELASTICSEARCH_URL/${CONTENTAPI_ELASTICSEARCH_INDEX}_items" | grep -q 404 && curl -sI $ELASTICSEARCH_URL/$CONTENTAPI_ELASTICSEARCH_INDEX | grep -q 404 ;}
}

_activate

if _missing_db; then
  cd {{repo}}
  set +e
  python manage.py initialize_data
  python manage.py create_user admin@example.com admin Admin Admin true
  set -e
else
  cd {{repo}}
  python manage.py initialize_data
  python manage.py data_upgrade
fi
