require "net/http"
require "nokogiri"

login_uri = URI.parse("https://www.itaulink.com.uy/appl/servlet/FeaServlet")
download_uri = URI.parse("https://www.itaulink.com.uy/appl/servlet/FeaServletDownload")

http = Net::HTTP.new(login_uri.host, login_uri.port)
http.set_debug_output $stdout
http.use_ssl = true

# Login

request = Net::HTTP::Post.new(login_uri.request_uri)
request.set_form_data({
  id: "login",
  tipo_usuario: "R",
  tipo_documento: "1",
  nro_documento: ENV["CI"],
  password: ENV["PASSWORD"]
})

response = http.request(request)
accounts = response["Location"]
cookie = response['Set-Cookie'].split('; ')[0]

# List accounts

accounts_uri = URI.parse(accounts)
request = Net::HTTP::Get.new(accounts_uri.request_uri)
request["Cookie"] = cookie
response = http.request(request)

parser = Nokogiri::HTML(response.body)
account_number = parser.search(".//td[./font[contains(.,'Pesos')]]/preceding-sibling::*").text
values = parser.search(".//td[./font[contains(.,'Pesos')]]/following-sibling::*").text.split

# Download account

request = Net::HTTP::Post.new(download_uri.request_uri)
request["Cookie"] = cookie
request.set_form_data({
  nro_cuenta: account_number,
  id: "bajar_archivo",
  mes_anio: "null",
  fecha: "",
  tipo_archivo: "E"
})

response = http.request(request)
puts response.body
