defmodule Beacon.Web.SitemapController do
  @moduledoc false
  use Beacon.Web, :controller

  def init(action) when action in [:index, :show], do: action

  def call(conn, :index) do
    conn
    |> accepts(["xml"])
    |> put_view(Beacon.Web.SitemapXML)
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public max-age=300")
    |> render(:sitemap_index, urls: get_sitemap_urls(conn))
  end

  def call(%{assigns: %{site: site}} = conn, :show) do
    conn
    |> accepts(["xml"])
    |> put_view(Beacon.Web.SitemapXML)
    |> put_resp_content_type("text/xml")
    |> put_resp_header("cache-control", "public max-age=300")
    |> render(:sitemap, pages: get_pages(conn, site))
  end

  defp get_sitemap_urls(conn) do
    Beacon.Registry.running_sites()
    |> Enum.filter(&beacon_router?/1)
    |> Enum.map(fn site ->
      routes_module = Beacon.Loader.fetch_routes_module(site)
      Beacon.apply_mfa(site, routes_module, :beacon_sitemap_url, [conn])
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  # a site can only be mounted by a router that uses `Beacon.Router`,
  # so sites configured with any other router have no sitemap to list
  defp beacon_router?(site) do
    %{router: router} = Beacon.Config.fetch!(site)
    Code.ensure_loaded?(router) and function_exported?(router, :__beacon_scoped_prefix_for_site__, 1)
  end

  defp get_pages(conn, site) do
    routes_module = Beacon.Loader.fetch_routes_module(site)

    site
    |> Beacon.Content.list_published_pages(per_page: :infinity)
    |> Enum.map(fn page ->
      url = Beacon.apply_mfa(site, routes_module, :beacon_page_url, [conn, page])

      %{
        loc: encode_control_characters(url),
        lastmod: DateTime.to_iso8601(page.updated_at)
      }
    end)
  end

  # a page path may contain control characters, which URLs do not allow
  # and most of which XML cannot represent at all, so they are percent-encoded
  defp encode_control_characters(url) do
    URI.encode(url, &(&1 > 0x1F and &1 != 0x7F))
  end
end
