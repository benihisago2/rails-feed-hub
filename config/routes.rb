Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Sidekiq's dashboard ships with no authentication of its own, so it is
  # mounted in development only. Exposing it anywhere else would hand anyone
  # who finds the path the ability to retry and delete jobs.
  if Rails.env.development?
    require "sidekiq/web"

    mount Sidekiq::Web => "/sidekiq"
  end

  # No destroy: removing a feed would take its articles with it, and nothing in
  # the application needs that yet. Deactivating is the reversible alternative
  # and is already an attribute of the form.
  resources :feeds, only: %i[index new create edit update] do
    # Fetching enqueues a job, so it is a POST rather than a link. A GET that
    # changes state is one prefetching browser or one crawler away from firing
    # itself, and nothing about the request tells the operator it happened.
    post :fetch, on: :member
  end

  # The CSV export is GET /articles.csv -- the format of the index, not a route
  # of its own, so it is filtered by whatever filters the index.
  resources :articles, only: %i[index]

  # No update or destroy: an import job is a record of something that happened,
  # and editing history is not a thing an operator should be able to do.
  resources :import_jobs, only: %i[index show create]

  # The feed list is the operator's home: everything else in the application is
  # downstream of which feeds are registered and whether they last fetched.
  root "feeds#index"
end
