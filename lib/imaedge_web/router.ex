defmodule ImaedgeWeb.Router do
  use ImaedgeWeb, :router

  pipeline :browser do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ImaedgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ImaedgeWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/collections", PageController, :create
    live "/i/:id", CollectionLive, :show
    get "/i/:id/export", ExportController, :show

    post "/i/:collection_id/uploads", UploadController, :create
    get "/i/:collection_id/uploads/:upload_id", UploadController, :show
    put "/i/:collection_id/uploads/:upload_id/chunks/:index", UploadController, :chunk
    post "/i/:collection_id/uploads/:upload_id/finalize", UploadController, :finalize
  end

  # Other scopes may use custom stacks.
  # scope "/api", ImaedgeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:imaedge, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ImaedgeWeb.Telemetry
    end
  end
end
