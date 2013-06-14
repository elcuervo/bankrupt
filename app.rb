require "./bankrupt"
require "tmpdir"
require "cuba"
require "cuba/render"
require 'zip/zip'

Cuba.plugin Cuba::Render
Cuba.define do
  on(root) { res.write view("home") }

  on post, "accounts" do
    account, password = req.params["username"], req.params["password"]
    company, company_password = req.params["company"], req.params["company_password"]

    bankrupt = Bankrupt.new(account, password, company, company_password)

    if !company.nil?
      bankrupt.company_login
    else
      bankrupt.login
    end

    puts "Fetching account information..."

    file_name = "#{account}.zip"
    compressed = Tempfile.new("#{account}-#{Time.now}")

    Zip::ZipOutputStream.open(compressed.path) do |zip|
      bankrupt.accounts.each do |account|
        zip.put_next_entry("#{account.number}.csv")
        zip.print account.balance_as_csv(req.params["month"])
      end
    end

    res["Content-Type"] = "application/zip"
    res["Content-Disposition"] = "attachment"

    res.write compressed.read

    compressed.close

  end
end
