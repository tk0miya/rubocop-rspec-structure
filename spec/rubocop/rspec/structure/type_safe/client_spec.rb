# frozen_string_literal: true

RSpec.describe RuboCop::RSpec::Structure::TypeSafe::Client do
  subject(:client) { described_class.new(api_key: "dummy", model: "jev-latest", timeout: 5) }

  let(:http) { instance_double(Net::HTTP) }
  let(:item) do
    noul_question(
      id: "result", state: "when the user is an admin", instructions: "does this describe a condition?", criteria: nil
    )
  end

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
  end

  def noul_question(**attrs)
    RuboCop::RSpec::Structure::TypeSafe::NoulQuestion.new(**attrs)
  end

  describe "#nouls" do
    context "with no items" do
      it "returns an empty hash without making a request" do
        expect(client.nouls([])).to eq({})
        expect(Net::HTTP).not_to have_received(:new)
      end
    end

    context "when the response is successful" do
      it "returns the probability keyed by id" do
        response = instance_double(Net::HTTPSuccess, body: '{"answers":{"result":{"noul":0.73}}}')
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(http).to receive(:request).and_return(response)

        probabilities = client.nouls([item])

        expect(probabilities).to eq({ "result" => 0.73 })
      end
    end

    context "when the request times out" do
      it "raises TimeoutError" do
        allow(http).to receive(:request).and_raise(Net::OpenTimeout)

        expect { client.nouls([item]) }.to raise_error(described_class::TimeoutError)
      end
    end

    context "when the HTTP response is not a success" do
      it "raises RequestError" do
        response = instance_double(Net::HTTPServerError, code: "500", body: "boom")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(http).to receive(:request).and_return(response)

        expect { client.nouls([item]) }.to raise_error(described_class::RequestError, /500/)
      end
    end

    context "when the JSON body is malformed" do
      it "raises RequestError" do
        response = instance_double(Net::HTTPSuccess, body: "not json")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(http).to receive(:request).and_return(response)

        expect { client.nouls([item]) }.to raise_error(described_class::RequestError)
      end
    end

    context "when the response is missing the expected field entirely" do
      it "raises RequestError" do
        response = instance_double(Net::HTTPSuccess, body: "{}")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(http).to receive(:request).and_return(response)

        expect { client.nouls([item]) }.to raise_error(described_class::RequestError, /missing/)
      end
    end

    context "with several items" do
      it "returns each item's probability keyed by its id" do
        body = '{"answers":{"a":{"noul":0.3},"b":{"noul":0.9}}}'
        response = instance_double(Net::HTTPSuccess, body:)
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(http).to receive(:request).and_return(response)

        probabilities = client.nouls(
          [
            noul_question(id: "a", state: "state a", instructions: "instructions a", criteria: nil),
            noul_question(id: "b", state: "state b", instructions: "instructions b", criteria: nil)
          ]
        )

        expect(probabilities).to eq({ "a" => 0.3, "b" => 0.9 })
      end
    end

    context "with an item whose state is meant to be checked in isolation" do
      it "sends one request with each item's state folded into its own instructions" do
        response = instance_double(Net::HTTPSuccess, body: '{"answers":{"a":{"noul":0.3}}}')
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        request = instance_double(Net::HTTP::Post)
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        sent_body = nil
        allow(request).to receive(:body=) { sent_body = _1 }
        allow(http).to receive(:request).with(request).and_return(response)

        client.nouls([noul_question(id: "a", state: "state a", instructions: "instructions a", criteria: nil)])

        payload = JSON.parse(sent_body)
        expect(payload["state"]).to eq("")
        expect(payload["questions"]["a"]["instructions"]).to include("instructions a", "state a")
      end
    end

    context "when the response is missing an item's field" do
      it "raises RequestError" do
        response = instance_double(Net::HTTPSuccess, body: '{"answers":{"a":{"noul":0.3}}}')
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(http).to receive(:request).and_return(response)

        expect do
          client.nouls(
            [
              noul_question(id: "a", state: "s", instructions: "i", criteria: nil),
              noul_question(id: "b", state: "s", instructions: "i", criteria: nil)
            ]
          )
        end.to raise_error(described_class::RequestError, /missing/)
      end
    end
  end
end
