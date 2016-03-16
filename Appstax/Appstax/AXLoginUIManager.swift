
import UIKit

class AXLoginUIManager {
    
    private var signupViewController: AXLoginViewController!
    private var loginViewController: AXLoginViewController!
    private var userService: AXUserService
    private var presentationRoot: UIViewController!
    private var navigationController: UINavigationController!
    private var completion: (()->())?
    
    init(userService: AXUserService) {
        self.userService = userService
        
        signupViewController = AXLoginViewController(manager: self)
        signupViewController.submitTitle = "Sign up"
        
        loginViewController = AXLoginViewController(manager: self)
        loginViewController.submitTitle = "Log in"
        loginViewController.goToLoginHidden = true
        
        navigationController = UINavigationController(rootViewController: signupViewController)
        navigationController.navigationBarHidden = true
    }
    
    func setupCustomViews(setup:((AXLoginViews!)->())?) {
        let views = AXLoginViews(size: loginViewController.view.bounds.size)
        setup?(views)
        signupViewController.backgroundView = views.signup
        signupViewController.backgroundView = views.login
    }
    
    func presentModalLoginWithViews(loginViews: ((AXLoginViews!)->())?, completion:()->()) {
        self.completion = completion
        dispatch_async(dispatch_get_main_queue()) {
            self.presentationRoot = UIApplication.sharedApplication().keyWindow?.rootViewController
            self.setupCustomViews(loginViews)
            self.presentationRoot.presentViewController(self.navigationController, animated: true, completion: nil)
        }
    }
    
    func viewControllerDidPressSubmitButton(viewController: AXLoginViewController) {
        if viewController === signupViewController {
            signupViewControllerDidPressSubmitButton()
        }
        if viewController === loginViewController {
            loginViewControllerDidPressSubmitButton()
        }
    }
    
    func viewControllerDidPressGoToLoginButton(viewController: AXLoginViewController) {
        navigationController.pushViewController(loginViewController, animated: true)
    }
    
    func signupViewControllerDidPressSubmitButton() {
        userService.signup(username: signupViewController.username, password: signupViewController.password, login: true, properties: [:]) {
            user, error in
            if let error = error {
                self.signupViewController.showError(error.userInfo["errorMessage"] as? String ?? "")
            } else {
                self.finish()
            }
        }
    }
    
    func loginViewControllerDidPressSubmitButton() {
        userService.login(username: loginViewController.username, password: loginViewController.password) {
            user, error in
            if let error = error {
                self.loginViewController.showError(error.userInfo["errorMessage"] as? String ?? "")
            } else {
                self.finish()
            }
        }
    }
    
    func finish() {
        presentationRoot.dismissViewControllerAnimated(true) {
            self.loginViewController.clear()
            self.signupViewController.clear()
        }
        completion?()
    }
}