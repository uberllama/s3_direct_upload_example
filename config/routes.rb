Rails.application.routes.draw do
  resources :documents, only: [:new, :create]
  get 'documents/:id/download/:filename', to: 'documents#download', constraints: { filename: /.+/ }, as: 'download_document'
  root to: 'documents#new'
end
