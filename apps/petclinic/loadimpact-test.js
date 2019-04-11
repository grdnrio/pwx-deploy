import { group, sleep } from 'k6';
import http from 'k6/http';

// Version: 1.2
// Creator: Load Impact v4.0 - k6 JS Test Script Recorder

// SET THIS VALUE
var host = "35.177.66.119:31382";
/// SET ^^ VALUE

export let options = {
    stages: [
        {
            "duration": "1m0s",
            "target": 10
        },
        {
            "duration": "5m0s",
            "target": 10
        }
    ],
    maxRedirects: 0,
    discardResponseBodies: true,
};

export default function() {

	group("page_0 - http://" + host + "/owners/new", function() {
		let req, res;
		req = [{
			"method": "post",
			"url": "http://" + host + "/owners/new",
			"body": {
				"address": Math.floor((Math.random() * 100) + 1) + " Hello Street",
				"city": "Portworx Town",
				"firstName": "First-" + Math.floor((Math.random() * 10) + 1),
				"lastName": "Last-" + Math.floor((Math.random() * 1000) + 1),
				"telephone": Math.floor(Math.random() * 10000000)
			},
			"params": {
				"headers": {
					"Origin": "http://${host}",
					"Upgrade-Insecure-Requests": "1",
					"Content-Type": "application/x-www-form-urlencoded",
					"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36",
					"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3"
				}
			}
		}];
		res = http.batch(req);
		// Random sleep between 5s and 10s
		sleep(Math.floor(Math.random()*1+5));
	});

}