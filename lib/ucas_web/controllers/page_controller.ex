defmodule UcasWeb.PageController do
  use UcasWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
