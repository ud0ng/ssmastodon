# frozen_string_literal: true

namespace :admin do
  get '/dashboard', to: 'dashboard#index'

  resources :domain_allows, only: [:new, :create, :destroy]
  resources :domain_blocks, only: [:new, :create, :destroy, :update, :edit] do
    collection do
      post :batch
    end
  end

  resources :export_domain_allows, only: [:new] do
    collection do
      get :export, constraints: { format: :csv }
      post :import
    end
  end

  resources :export_domain_blocks, only: [:new] do
    collection do
      get :export, constraints: { format: :csv }
      post :import
    end
  end

  resources :email_domain_blocks, only: [:index, :new, :create] do
    collection do
      post :batch
    end
  end

  resources :action_logs, only: [:index]
  resources :warning_presets, except: [:new, :show]

  namespace :terms_of_service do
    resource :generate, only: [:show, :create]
    resource :history, only: [:show]
    resource :draft, only: [:show, :update]
  end

  resources :terms_of_service, only: [:index] do
    resource :preview, only: [:show], module: :terms_of_service
    resource :test, only: [:create], module: :terms_of_service
    resource :distribution, only: [:create], module: :terms_of_service
  end

  resources :announcements, except: [:show] do
    member do
      post :publish
      post :unpublish
    end

    resource :preview, only: [:show], module: :announcements
    resource :test, only: [:create], module: :announcements
    resource :distribution, only: [:create], module: :announcements
  end

  with_options to: redirect('/admin/settings/branding') do
    get '/settings'
    get '/settings/edit'
  end

  namespace :settings do
    resource :branding, only: [:show, :update], controller: 'branding'
    resource :registrations, only: [:show, :update], controller: 'registrations'
    resource :content_retention, only: [:show, :update], controller: 'content_retention'
    resource :about, only: [:show, :update], controller: 'about'
    resource :appearance, only: [:show, :update], controller: 'appearance'
    resource :discovery, only: [:show, :update], controller: 'discovery'
    resource :community, only: [:show, :update], controller: 'community'
    resource :community_theme, only: [:show, :update], controller: 'community_theme'
  end

  # 자동봇 시트 (관리 > 시트 설정)
  resource :bot_sheet_connection, path: 'sheets/connection', only: [:show, :update], controller: 'bot_sheets/connections'
  resources :bot_sheets, path: 'sheets', only: [:index, :show, :update], constraints: { id: /main|reservation|story|investigation/ } do
    member do
      post :rows, action: :append
      patch :rows, action: :update_row
      delete :rows, action: :destroy_row
    end
  end

  # 게임 (시스템 계정)
  get 'games/houses', to: redirect('/admin/characters/houses')
  resources :game_houses, path: 'characters/houses', only: [:index, :create, :update, :destroy] do
    member do
      post :effects, action: :add_effect, as: :add_effect
      patch 'effects/:index', action: :update_effect, as: :effect
      delete 'effects/:index', action: :remove_effect
    end
    post :adjust, on: :collection
    post :scoring, on: :collection
    post :mode, on: :collection
    patch :labels, on: :collection
  end
  resources :game_seasons, path: 'characters/seasons', only: [:create, :update, :destroy] do
    member do
      post :interim
      post :finish
    end
    patch :messages, on: :collection
  end
  # 상점 설정 (관리 > 시스템 > 상점 설정): 설정 · 명령어 · 상점 목록 · 재화 기록 · 아이템 기록
  get 'games/shops', to: redirect('/admin/shop/list')
  get 'shop', to: redirect('/admin/shop/settings')
  get 'shop/settings', to: 'game_shops#settings', as: :game_shop_settings
  get 'shop/commands', to: 'game_shops#commands', as: :game_shop_commands
  get 'shop/records', to: 'game_shop_records#money', as: :game_shop_money_records
  get 'shop/item_records', to: 'game_shop_records#items', as: :game_shop_item_records
  get 'shop/counter_records', to: 'game_shop_records#counters', as: :game_shop_counter_records
  resources :game_shops, path: 'shop/list', only: [:index, :create, :update, :destroy] do
    patch :currency, on: :collection
  end
  resources :game_shop_items, path: 'games/shop_items', only: [:create, :update, :destroy]
  resources :game_effects, path: 'shop/effects', only: [:index, :create, :update, :destroy]
  resources :game_counters, path: 'shop/counters', only: [:index, :create, :update, :destroy] do
    resources :rules, controller: 'game_counter_rules', only: [:create, :update, :destroy]
  end
  resources :game_sessions, path: 'games/sessions', only: [] do
    member do
      post :advance
      post :cancel
      post :draw
      post :decide
    end
  end
  resource :game_event, path: 'games/event', only: [:create]
  get 'events', to: 'game_events#index', as: :game_events_settings
  get 'events/records', to: 'game_events#records', as: :game_event_records
  resource :game_staff, path: 'settings/staff', only: [:update], controller: 'game_staff'
  resources :game_settings, path: 'games', only: [:index, :show, :update]
  resources :game_activities, path: 'characters/activity', only: [:index, :show] do
    get :stats, on: :member
    post :backfill, on: :collection
    post :give, on: :collection
    patch :criteria, on: :collection
  end
  resources :game_character_stats, path: 'characters/stats', only: [:index, :create, :update, :destroy]
  get 'characters/activity_log', to: 'game_activity_logs#index', as: :game_activity_logs
  get 'characters/house_records', to: 'game_house_records#index', as: :game_house_records
  get 'characters/records', to: 'game_records#index', as: :game_records
  resources :game_characters, path: 'characters', only: [:index, :edit, :update] do
    # 상세 > 인벤토리 카드: 아이템 더하기·고치기·지우기 (index = 인벤토리 안 순서)
    member do
      patch :group, action: :assign_group
      post :items, action: :add_item
      patch :money, action: :set_money
      post :effects, action: :add_effect, as: :add_effect
      patch 'effects/:index', action: :update_effect, as: :effect
      delete 'effects/:index', action: :remove_effect
      patch 'items/:index', action: :update_item, as: :item
      delete 'items/:index', action: :remove_item
    end
  end

  resources :site_uploads, only: [:destroy]

  resources :invites, only: [:index, :create, :destroy] do
    collection do
      post :deactivate_all
    end
  end

  resources :relays, only: [:index, :new, :create, :destroy] do
    member do
      post :enable
      post :disable
    end
  end

  resources :instances, only: [:index, :show, :destroy], constraints: { id: %r{[^/]+} }, format: 'html' do
    member do
      post :clear_delivery_errors
      post :restart_delivery
      post :stop_delivery
    end
  end

  resources :rules, only: [:index, :new, :create, :edit, :update, :destroy]

  resources :webhooks do
    member do
      post :enable
      post :disable
    end

    resource :secret, only: [], controller: 'webhooks/secrets' do
      post :rotate
    end
  end

  resources :reports, only: [:index, :show] do
    resources :actions, only: [:create], controller: 'reports/actions' do
      collection do
        post :preview
      end
    end

    member do
      post :assign_to_self
      post :unassign
      post :reopen
      post :resolve
    end
  end

  resources :report_notes, only: [:create, :destroy]

  resources :accounts, only: [:index, :show, :destroy] do
    member do
      post :enable
      post :unsensitive
      post :unsilence
      post :unsuspend
      post :redownload
      post :remove_avatar
      post :remove_header
      post :memorialize
      post :approve
      post :reject
      post :unblock_email
      post :toggle_protect
    end

    collection do
      post :batch
    end

    resource :change_email, only: [:show, :update]
    resource :reset, only: [:create]
    resource :action, only: [:new, :create], controller: 'account_actions'

    resources :statuses, only: [:index, :show] do
      collection do
        post :batch
      end
    end

    resources :relationships, only: [:index]

    resource :confirmation, only: [:create] do
      collection do
        post :resend
      end
    end
  end

  resources :users, only: [] do
    scope module: :users do
      resource :two_factor_authentication, only: [:destroy]
      resource :role, only: [:show, :update]
    end
  end

  resources :custom_emojis, only: [:index, :new, :create] do
    collection do
      post :batch
    end
  end

  # DM 운영 관리
  resources :direct_messages, only: [:index]

  resources :ip_blocks, only: [:index, :new, :create] do
    collection do
      post :batch
    end
  end

  resources :roles, except: [:show]
  resources :account_moderation_notes, only: [:create, :destroy]
  resources :tags, only: [:index, :show, :update]

  namespace :disputes do
    resources :appeals, only: [:index] do
      member do
        post :approve
        post :reject
      end
    end
  end

  resources :software_updates, only: [:index]
end
