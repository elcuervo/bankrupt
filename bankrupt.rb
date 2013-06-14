#!/usr/bin/env ruby

require "net/http"
require "csv"
require "nokogiri"

Bankrupt = Struct.new(:id, :password, :company, :company_password) do
  TYPES = %w(Pesos lares)
  DATE_MAP = { JAN: 1, FEB: 2, MAR: 3, APR: 4, MAY: 5, JUN: 6, JUL: 7, AUG: 8,
               SEP: 9, OCT: 10, NOV: 11, DEC: 12 }

  Account = Struct.new(:currency, :number, :balance) do
    Balance = Struct.new(:date, :amount, :description)

    def balance_from_itau(month)
      url = "https://www.itaulink.com.uy/appl/servlet/FeaServletDownload"
      year = Time.now.year

      response = Bankrupt.post(url, {
        nro_cuenta: number,
        id: "bajar_archivo",
        mes_anio: "#{month}#{year}",
        dias: 10,
        fecha: "",
        tipo_archivo: "E"
      })

      response.body
    end

    def balance_as_csv(month = Time.now.month - 1)
      csv = %w(Date Amount Description).to_csv

      balance(month).each do |item|
        csv << [item.date, item.amount, item.description].to_csv
      end

      csv
    end

    def fix_date(date)
      day = date[0..1]
      month = date[2..4].to_sym
      year = "20" + date[5..6]

      "#{DATE_MAP[month]}/#{day}/#{year}"
    end

    def balance(month)
      balances = []

      CSV.parse(balance_from_itau(month), headers: true) do |row|
        puts row
        date = fix_date(row["FECHA"])
        amount = row["HABER"].to_f - row["DEBE"].to_f
        description = row["CONCEPTO"]

        balances << Balance.new(date, amount, description)
      end

      balances[1...-1]
    end

  end

  class << self
    attr_accessor :cookie

    def http
      @_http ||= begin
        uri = URI.parse("https://www.itaulink.com.uy/")
        http = Net::HTTP.new(uri.host, uri.port)
        http.set_debug_output $stdout if ENV["DEBUG"]
        http.use_ssl = true
        http
      end
    end

    def get(url)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Cookie"] = Bankrupt.cookie if Bankrupt.cookie

      self.http.request(request)
    end

    def post(url, data)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data(data)
      request["Cookie"] = Bankrupt.cookie if Bankrupt.cookie

      self.http.request(request)
    end
  end

  def login
    response = Bankrupt.post("https://www.itaulink.com.uy/appl/servlet/FeaServlet", {
      id: "login",
      tipo_usuario: "R",
      tipo_documento: "1",
      nro_documento: id,
      password: password
    })

    cookie = response['Set-Cookie'].split('; ')[0]
    @accounts_url = response["Location"]

    Bankrupt.cookie = cookie
  end

  def company_login
    response = Bankrupt.post("https://www.itaulink.com.uy/appl/servlet/FeaServlet", {
      id: "login",
      tipo_usuario: "C",
      empresa: company.upcase,
      empresa_aux: company,
      pwd_empresa: company_password,
      usuario: id,
      usuario_aux: id,
      pwd_usuario: password
    })

    cookie = response['Set-Cookie'].split('; ')[0]
    @accounts_url = response["Location"]

    Bankrupt.cookie = cookie
  end

  def accounts
    @_accounts ||= begin
      response = Bankrupt.get(@accounts_url)
      parser = Nokogiri::HTML(response.body)
      accounts = []

      TYPES.each do |type|
        locations = ".//td[./font[contains(.,'#{type}')]]"
        parser.search(locations).each do |location|
          rows = location.parent.search("td")
          number = rows.first.text
          balance = rows[2].text

          accounts << Account.new(type, number, balance)
        end
      end

      puts "There are #{accounts.size} accounts. (#{accounts.map(&:number).join(",")})"

      accounts
   end
  end
end

if __FILE__ == $0
  account_id = ENV.fetch("CI", $1)
  password = ENV.fetch("PASSWORD", $2)

  bankrupt = Bankrupt.new(account_id, password)
  bankrupt.login
  puts "Fetching account information..."

  bankrupt.accounts.each do |account|
    filename = "#{account.number}.csv"
    open(filename, "w") << account.balance_as_csv

    puts "#{filename} exported"
  end
end
