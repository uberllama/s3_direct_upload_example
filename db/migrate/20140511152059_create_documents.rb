class CreateDocuments < ActiveRecord::Migration
  def change
    create_table :documents do |t|
      t.string :direct_upload_url, null: false
      t.attachment :upload
      t.boolean :processed, default: false, null: false
      t.timestamps
    end
    add_index :documents, :processed
  end
end
