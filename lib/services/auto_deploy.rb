class Service::AutoDeploy < Service::HttpPost
  password :github_token
  string   :environments
  boolean  :deploy_on_push, :deploy_on_status

  white_list :deploy_on_push, :deploy_on_status

  default_events :push, :status

  url 'https://github.com/atmos'
  logo_url 'https://camo.githubusercontent.com/edbc46e94fd4e9724da99bdd8da5d18e82f7b737/687474703a2f2f7777772e746f756368696e737069726174696f6e2e636f6d2f6173736574732f6865726f6b752d6c6f676f2d61663863386230333462346261343433613632376232393035666337316138362e706e67'

  maintained_by :github => 'atmos', :twitter => '@atmos'

  supported_by :web => 'https://github.com/contact',
    :email => 'support@github.com',
    :twitter => '@atmos'

  def github_repo_path
    [ payload['repository']['owner']['name'], 
      payload['repository']['name'] ].join('/')
  end

  def environment_names
    @environment_names ||= required_config_value("environments").split(',')
  end

  def payload_ref
    payload['ref'].split('/').last
  end

  def sha
    payload['after'][0..7]
  end

  def pusher_name
    payload['pusher']['name']
  end

  def default_branch?
    payload_ref == payload['repository']['default_branch']
  end

  def deploy_on_push?
    true
  end
  
  def version_string
    payload_ref == sha ? sha : "#{payload_ref}@#{sha}"
  end

  def receive_event
    return unless default_branch?

    http.ssl[:verify] = true

    case event
    when :push
      github_user_access?
      github_repo_deployment_access?
      deploy_from_push_payload if deploy_on_push?
    else
      raise_config_error_with_message(:no_event_handler)
    end
  end

  def push_deployment_description
    "Auto-Deployed by GitHub Services@#{Service.current_sha[0..7]} for #{pusher_name} - #{version_string}"
  end

  def deploy_from_push_payload
    environment_names.each do |environment_name|
      deployment_options = {
        "ref"               => sha,
        "environment"       => environment_name,
        "description"       => push_deployment_description,
        "required_contexts" => [ ]
      }
      create_deployment_for_options(deployment_options)
    end
  end

  def create_deployment_for_options(options)
    deployment_path = "/repos/#{github_repo_path}/deployments"
    response = http_post "https://api.github.com#{deployment_path}" do |req|
      req.headers.merge!(default_github_headers)
      req.body = JSON.dump(options)
    end
    raise_config_error_with_message(:no_github_deployment_access) unless response.success?
  end

  def github_user_access?
    response = github_get("/user")
    unless response.success?
      raise_config_error_with_message(:no_github_user_access)
    end
  end

  def github_repo_deployment_access?
    response = github_get("/repos/#{github_repo_path}/deployments")
    unless response.success?
      raise_config_error_with_message(:no_github_repo_deployment_access)
    end
  end

  def github_get(path)
    http_get "https://api.github.com#{path}" do |req|
      req.headers.merge!(default_github_headers)
    end
  end

  def default_github_headers
    {
      'Accept'        => "application/vnd.github.cannonball-preview+json",
      'User-Agent'    => "Operation: California Auto-Deploy",
      'Content-Type'  => "application/json",
      'Authorization' => "token #{required_config_value('github_token')}"
    }
  end

  def raise_config_error_with_message(sym)
    raise_config_error(error_messages[sym])
  end

  def error_messages
    @default_error_messages ||= {
      :no_event_handler =>
        "The #{event} event is currently unsupported.",
      :no_github_user_access =>
        "Unable to access GitHub with the provided token.",
      :no_github_repo_deployment_access =>
        "Unable to access the #{github_repo_path} repository's deployments on GitHub with the provided token.",
      :no_github_repo_deployment_status_access =>
        "Unable to update the deployment status on GitHub with the provided token."
    }
  end
end
