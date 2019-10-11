#!/bin/bash
#------------------------------------------------------
# s3-multi-upload.bash
#
# 処理概要:　大容量のファイルを分割しS3にマルチアップロードする
#------------------------------------------------------
source ./CONFIG.ini &> /dev/null
#------------------------------------------------------------------------------
# 走行ログの記録
[[ ! -d ./LOG ]] && mkdir ./LOG
[[ ! -d ./tmp ]] && mkdir ./tmp
[[ ! -d ./dist ]] && mkdir ./dist

cur_time=$(date +%Y%m%d%H%M%S | cut -c 1-18)
log_file=./LOG/LOG.$(basename ${0}).$cur_time
exec 2> $log_file ; set -xv
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# 変数定義
tmp=./tmp/$cur_time-$$
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# ファイルの分割とリネーム
split -b 500m -a 3 ${FILE_PATH} ./dist/chunk.
[[ $? -ne 0 ]] && exit 1
ls ./dist/chunk.* | LANG=C sort | nl | awk '{ printf("%s ./dist/chunk-%s.dmp\n", $2, $1, $2) }' | xargs -n 2 mv
[[ $? -ne 0 ]] && exit 1
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# S3マルチアップロードセッションの開始
SESSION_JSON=$(aws s3api create-multipart-upload \
    --bucket ${S3_BUCKET_NAME} \
    --key ${OBJECT_NAME} \
    --storage-class GLACIER \
)
[[ $? -ne 0 ]] && exit 1
# 変数の設定
UPLOAD_ID=$(echo ${SESSION_JSON} | jq -r '.UploadId')
[[ $? -ne 0 ]] && exit 1
KEY=$(echo ${SESSION_JSON} | jq -r '.Key')
[[ $? -ne 0 ]] && exit 1
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# 分割してアップロード
ls ./dist | LANG=C sort -t '-' -k2,2n | nl | while read line
do
    num=$(echo ${line} | cut -d' ' -f1)
    file=$(echo ${line} | cut -d' ' -f2)
    # UPLOAD
    aws s3api upload-part \
        --bucket ${S3_BUCKET_NAME} \
        --key ${KEY} \
        --upload-id ${UPLOAD_ID} \
        --part-number ${num} \
        --body ./dist/${file}
    [[ $? -ne 0 ]] && exit 1
done
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# セッションを終了する
multipart=$(aws s3api list-parts \
    --bucket ${S3_BUCKET_NAME} \
    --key ${KEY} \
    --upload-id ${UPLOAD_ID} | jq '{ "Parts": [ .Parts[] | { ETag, PartNumber } ] }')
[[ $? -ne 0 ]] && exit 1

aws s3api complete-multipart-upload \
   --bucket ${S3_BUCKET_NAME} \
    --key ${KEY} \
    --upload-id ${UPLOAD_ID} \
    --multipart-upload "${multipart}"
[[ $? -ne 0 ]] && exit 1
#------------------------------------------------------------------------------
rm -rf $tmp-*
rm -rf ./dist/*
exit 0
