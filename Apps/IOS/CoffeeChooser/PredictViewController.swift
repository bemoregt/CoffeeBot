	//
//  PredictViewController.swift
//  CoffeeChooser
//
//  Created by Antonio Hung on 12/27/17.
//  Copyright © 2017 Dark Bear Interactive. All rights reserved.
//

import UIKit
import CoreLocation
import SwiftyJSON
import CoreML
import Firebase

class PredictViewController: SuperViewController {

	var lastLocation:CLLocationCoordinate2D?

	@IBOutlet weak var iconHeightConstraint: NSLayoutConstraint!
	@IBOutlet weak var class_image: UIImageView!
	@IBOutlet weak var predict_label: UILabel!
	var weatherView:WeatherViewController? {
		didSet {
			weatherView?.view.isHidden = true
		}
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
		_ = LocationManager.shared.getLocation()
		if (Int((UIApplication.shared.windows.first?.frame.size.height)!) < 600) {
			iconHeightConstraint.constant = 200
		}

		NotificationCenter.default.addObserver(self, selector: #selector(locationUpdated(notification:)), name: .locationDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(locationStatusChanged(notification:)), name: Notification.Name.locationStatusChanged, object: nil)
		
		NotificationCenter.default.addObserver(self, selector: #selector(locationError(notification:)), name: Notification.Name.locationDidFail, object: nil)
		
//		let alertShown = UserDefaults.standard.bool(forKey: "didViewCreateAccountAlert")
//		if ((Auth.auth().currentUser?.isAnonymous)! && !alertShown) {
//			let alert = UIAlertController(title: "You haven't created an account yet", message: "Creating an account will allow the app to perform coffee predictions specificly to your preferences", preferredStyle: .alert)
//			alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (alert) in
//				let storyboard = UIStoryboard.init(name: "Main", bundle: nil)
//				var vc:UIViewController?
//				vc = storyboard.instantiateViewController(withIdentifier: "Login")
//				let window = UIApplication.shared.windows.first
//				window?.rootViewController = vc
//				window?.makeKeyAndVisible()
//			}))
//			alert.addAction(UIAlertAction(title: "No Thanks", style: .cancel, handler:nil))
//			UserDefaults.standard.set(true, forKey: "didViewCreateAccountAlert")
//
//			present(alert, animated: true, completion: nil)
//		}
    }
	
	func locationUpdated(notification: NSNotification) {
		guard let location = notification.userInfo!["location"] as? CLLocationCoordinate2D else {
			return
		}
		lastLocation = location
		predict(location)
 	}
	
	func locationStatusChanged(notification: NSNotification) {
		guard let status = notification.userInfo!["status"] as? CLAuthorizationStatus else {
			return
		}
		
		if status == .denied {
			presentAlert(title: "Location Access required", message: "Access to your current location is required")
			self.predict_label.text = "Location Not Determined"
			self.class_image.image = self.class_image.image?.Noir()
			
		}
	}
	
	func locationError(notification:Notification) {
		presentAlert(title: "Unable to aquire location", message: "Please try again.")
		self.predict_label.text = "Location Not Determined"
	}
	
	@IBAction func predictAction(_ sender: Any) {
		_ = LocationManager.shared.getLocation()
	}
	
	func predict(_ location:CLLocationCoordinate2D) {
	
		self.class_image.image = nil
		self.predict_label.text = ""
		
		guard let location = self.lastLocation else {
			return
		}
		
			
		OpenWeatherAPI.sharedInstance.weatherDataFor(location: location, completion: {
			(response: JSON?) in
			
			guard let json = response else {
				return
			}
			
			self.weatherView?.weatherData = json
			self.weatherView?.view.isHidden = false

			
			if #available(iOS 11.0, *) {
				let model = coffee_prediction()
				guard let mlMultiArray = try? MLMultiArray(shape:[13,1], dataType:MLMultiArrayDataType.double) else {
					fatalError("Unexpected runtime error. MLMultiArray")
				}
				var values = [json["clouds"]["all"].doubleValue,
							  json["main"]["humidity"].doubleValue,
							  round(json["main"]["temp"].doubleValue),
							  round(json["visibility"].doubleValue / 1609.344),
							  round(json["wind"]["speed"].doubleValue),
							]
				
				values.append(contentsOf: self.toOneHot(json["weather"][0]["main"].stringValue))
				for (index, element) in values.enumerated() {
					mlMultiArray[index] = NSNumber(floatLiteral: element )
				}
				let input = coffee_predictionInput(input: mlMultiArray)
				guard let prediction = try? model.prediction(input: input) else {
					return
				}
				
				let result = prediction
				print("classLabel \(result.classLabel)")
				
				if result.classLabel == 1 {
					self.class_image.image = UIImage.init(named: "coffee_hot")
					self.predict_label.text = "Hot Coffee"
				} else {
					self.class_image.image = UIImage.init(named: "coffee_iced")
					self.predict_label.text = "Iced Coffee"
				}
				
				let percent = Int(round(result.classProbability[result.classLabel]! * 100))
				 self.predict_label.text = self.predict_label.text! + "\n(\(percent)% probability)"
				print(result.classProbability)
//				self.predict_label.text = self.predict_label.text
				let loc = CLLocation(latitude: location.latitude, longitude: location.longitude)
				print("loc",loc)

				CLGeocoder().reverseGeocodeLocation(loc, completionHandler: {(placemarks, error) -> Void in
					
					if error != nil {
						print("Reverse geocoder failed with error" + (error?.localizedDescription)!)
						return
					}
					
					guard let pm = placemarks?.first, let locality = pm.locality, let administrativeArea = pm.administrativeArea else {
						return
					}
					self.weatherView?.locationLabel.text = locality + ", " + administrativeArea
					
				})
			} else {
				// Fallback on earlier versions
			}
		})
	}
	
	func toOneHot(_ string:String) -> [Double] {
		var str = string
		var items = [Double](repeating: 0.0, count: 7)
		let weather_conds:[String] = ["Clear", "Clouds", "Fog", "Haze", "Rain", "Smoke", "Snow", "Thunderstorm"]
		
		if str.lowercased().range(of:"cloud") != nil || str.lowercased().range(of:"overcast") != nil{
			str = "Clouds"
		}
		
		if str.lowercased().range(of:"snow") != nil {
			str = "Snow"
		}
		
		if str.lowercased().range(of:"rain") != nil  || str.lowercased().range(of:"drizzle") != nil || str.lowercased().range(of:"mist") != nil{
			str = "Rain"
		}
		
		if str.lowercased().range(of:"none") != nil {
			str = "Clear"
		}

		guard let index = weather_conds.index(of: str) else {
			items[0] = 1
			return items
		}
		
		items[index] = 1
		return items
	}
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

	
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if segue.identifier == "weatherView" {
			weatherView = segue.destination as? WeatherViewController
		}
	}
	

}
