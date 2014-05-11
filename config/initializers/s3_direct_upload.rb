S3DirectUpload.config do |c|
  c.access_key_id     = Rails.application.secrets.aws['access_key_id']
  c.secret_access_key = Rails.application.secrets.aws['secret_access_key']
  c.bucket            = Rails.application.secrets.aws['s3_bucket_name']
  c.region            = "s3"
end