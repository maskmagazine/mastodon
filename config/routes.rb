# frozen_string_literal: true

require 'sidekiq/web'

Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: 'letter_opener' if Rails.env.development?

  authenticate :user, lambda { |u| u.admin? } do
    mount Sidekiq::Web, at: 'sidekiq', as: :sidekiq
    mount PgHero::Engine, at: 'pghero', as: :pghero
  end

  use_doorkeeper do
    controllers authorizations: 'oauth/authorizations', authorized_applications: 'oauth/authorized_applications'
  end

  get '.well-known/host-meta', to: 'xrd#host_meta', as: :host_meta
  get '.well-known/webfinger', to: 'xrd#webfinger', as: :webfinger, defaults: { format: 'json' }

  devise_for :users, path: 'auth', controllers: {
    sessions:           'auth/sessions',
    registrations:      'auth/registrations',
    passwords:          'auth/passwords',
    confirmations:      'auth/confirmations',
  }

  get '/users/:username', to: redirect('/@%{username}'), constraints: { format: :html }

  resources :accounts, path: 'users', only: [:show], param: :username do
    resources :stream_entries, path: 'updates', only: [:show] do
      member do
        get :embed
      end
    end

    get :remote_follow,  to: 'remote_follow#new'
    post :remote_follow, to: 'remote_follow#create'

    member do
      get :followers
      get :following

      post :follow
      post :unfollow
    end
  end

  get '/@:username', to: 'accounts#show', as: :short_account
  get '/@:account_username/:id', to: 'statuses#show', as: :short_account_status

  namespace :settings do
    resource :profile, only: [:show, :update]
    resource :preferences, only: [:show, :update]
    resource :import, only: [:show, :create]

    resource :export, only: [:show]
    namespace :exports, constraints: { format: :csv } do
      resources :follows, only: :index, controller: :following_accounts
      resources :blocks, only: :index, controller: :blocked_accounts
    end

    resource :two_factor_auth, only: [:show, :new, :create] do
      member do
        post :disable
      end
    end
  end

  resources :media, only: [:show]
  resources :tags,  only: [:show]

  # Remote follow
  get  :authorize_follow, to: 'authorize_follow#new'
  post :authorize_follow, to: 'authorize_follow#create'

  namespace :admin do
    resources :pubsubhubbub, only: [:index]
    resources :domain_blocks, only: [:index, :new, :create]
    resources :settings, only: [:index, :update]

    resources :reports, only: [:index, :show] do
      member do
        post :resolve
        post :silence
        post :suspend
        post :remove
      end
    end

    resources :accounts, only: [:index, :show] do
      member do
        post :silence
        post :unsilence
        post :suspend
        post :unsuspend
      end
    end
  end

  get '/admin', to: redirect('/admin/settings', status: 302)

  namespace :api do
    # PubSubHubbub outgoing subscriptions
    resources :subscriptions, only: [:show]
    post '/subscriptions/:id', to: 'subscriptions#update'

    # PubSubHubbub incoming subscriptions
    post '/push', to: 'push#update', as: :push

    # Salmon
    post '/salmon/:id', to: 'salmon#update', as: :salmon

    # OEmbed
    get '/oembed', to: 'oembed#show', as: :oembed

    # JSON / REST API
    namespace :v1 do
      resources :statuses, only: [:create, :show, :destroy] do
        member do
          get :context
          get :card
          get :reblogged_by
          get :favourited_by

          post :reblog
          post :unreblog
          post :favourite
          post :unfavourite
        end
      end

      get '/timelines/home',     to: 'timelines#home', as: :home_timeline
      get '/timelines/public',   to: 'timelines#public', as: :public_timeline
      get '/timelines/tag/:id',  to: 'timelines#tag', as: :hashtag_timeline

      get '/search', to: 'search#index', as: :search

      resources :follows,    only: [:create]
      resources :media,      only: [:create]
      resources :apps,       only: [:create]
      resources :blocks,     only: [:index]
      resources :mutes,      only: [:index]
      resources :favourites, only: [:index]
      resources :reports,    only: [:index, :create]

      resource :instance, only: [:show]

      resources :follow_requests, only: [:index] do
        member do
          post :authorize
          post :reject
        end
      end

      resources :notifications, only: [:index, :show] do
        collection do
          post :clear
        end
      end

      resources :accounts, only: [:show] do
        collection do
          get :relationships
          get :verify_credentials
          patch :update_credentials
          get :search
        end

        member do
          get :statuses
          get :followers
          get :following

          post :follow
          post :unfollow
          post :block
          post :unblock
          post :mute
          post :unmute
        end
      end
    end

    namespace :web do
      resource :settings, only: [:update]
    end
  end

  get '/web/(*any)', to: 'home#index', as: :web

  get '/about',      to: 'about#show'
  get '/about/more', to: 'about#more'
  get '/terms',      to: 'about#terms'

  root 'home#index'

  match '*unmatched_route',
    via: :all,
    to: 'application#raise_not_found',
    format: false
end
