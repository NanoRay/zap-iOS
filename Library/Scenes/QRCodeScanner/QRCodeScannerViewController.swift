//
//  Zap
//
//  Created by Otto Suess on 22.01.18.
//  Copyright © 2018 Otto Suess. All rights reserved.
//

import Lightning
import SwiftBTC
import UIKit
import mantaswift

class QRCodeScannerViewController: UIViewController {
    // swiftlint:disable implicitly_unwrapped_optional
    private weak var scannerView: QRCodeScannerView!
    weak var pasteButton: UIButton!
    // swiftlint:enable implicitly_unwrapped_optional
    
    // loading views
    private weak var loadingView: LoadingAnimationView?
    private weak var loadingViewCenterYConstraint: NSLayoutConstraint?
    
    private var mantaWallet: MantaWallet?
    
    private let strategy: QRCodeScannerStrategy
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    init(strategy: QRCodeScannerStrategy) {
        self.strategy = strategy
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        title = strategy.title
        
        navigationController?.navigationBar.backgroundColor = .clear
        navigationController?.navigationBar.shadowImage = UIImage()
        navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped(_:)))
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: Asset.iconFlashlight.image, style: .plain, target: self, action: #selector(toggleTorch))
        
        setupScannerView()
        setupPasteButton()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        
        scannerView.presentWarningIfAccessDenied(on: self)
    }
    
    private func setupScannerView() {
        let scannerView = QRCodeScannerView(frame: .zero)
        view.addAutolayoutSubview(scannerView)
        scannerView.constrainEdges(to: view)
        
        scannerView.handler = { [weak self] address in
            self?.checkAddress(for: address)
        }
        
        self.scannerView = scannerView
    }
    
    private func setupPasteButton() {
        let pasteButton = UIButton(type: .system)
        pasteButton.setTitle(strategy.pasteButtonTitle, for: .normal)
        Style.Button.background.apply(to: pasteButton)
        
        view.addAutolayoutSubview(pasteButton)
        
        NSLayoutConstraint.activate([
            pasteButton.heightAnchor.constraint(equalToConstant: 56),
            pasteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(equalTo: pasteButton.trailingAnchor, constant: 20),
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: pasteButton.bottomAnchor, constant: 20)
        ])
        
        pasteButton.addTarget(self, action: #selector(pasteButtonTapped(_:)), for: .touchUpInside)
        
        self.pasteButton = pasteButton
    }
    
    private func presentLoading() {
        UIView.animate(withDuration: 0.2, animations: { [weak self] in
            self?.scannerView.alpha = 0
            }, completion: { [weak self] _ in
                self?.scannerView.isHidden = true
        })
        
        let loadingImage: ImageAsset
        loadingImage = Asset.loadingAppia
        
        let size = CGSize(width: 50, height: 50)
        let loadingView = LoadingAnimationView(frame: CGRect(origin: .zero, size: size), loadingImage: loadingImage)
        loadingView.startAnimating()
        view.addAutolayoutSubview(loadingView)
        
        loadingView.constrainSize(to: size)
        
        let centerYConstraint = loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        self.loadingViewCenterYConstraint = centerYConstraint
        
        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerYConstraint
        ])
        
        self.loadingView = loadingView
    }
    
    private func recoverFromLoadingState() {
        scannerView.isHidden = false
        
        UIView.animate(withDuration: 0.2) { [weak self] in
            self?.scannerView.alpha = 1
        }
        
        loadingView?.removeFromSuperview()
    }
    
    func checkAddress(for address: String) {
        mantaWallet = MantaWallet(address)
        
        if mantaWallet != nil {
            presentLoading()
            mantaWallet?.getPaymentRequest(cryptoCurrency: "BTC-LN-TESTNET").timeout(5).then { envelope in
                self.recoverFromLoadingState()
                let mantaRequest = try? envelope.unpack()
                
                let mantaDestinationAddress = mantaRequest?.destinations[0].destinationAddress ?? ""
                self.tryPresentingViewController(for: mantaDestinationAddress, mantaRequest: mantaRequest)
                
            }.catch { error in
                self.recoverFromLoadingState()
                self.mantaWallet = nil
                self.presentError(message: error.localizedDescription)
            }
        } else {
            tryPresentingViewController(for: address)
        }
    }
    
    func tryPresentingViewController(for address: String, mantaRequest: PaymentRequestMessage? = nil) {
        
        strategy.viewControllerForAddress(address: address, extra: mantaRequest) { [weak self] result in
            DispatchQueue.main.async {
                self?.pasteButton.isEnabled = true
                switch result {
                case .success(let viewController):
                    self?.presentViewController(viewController)
                    self?.scannerView.stop()
                    UISelectionFeedbackGenerator().selectionChanged()
                case .failure(let error):
                    self?.presentError(message: error.message)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
    
    func presentViewController(_ viewController: UIViewController) {
        guard let modalDetailViewController = viewController as? ModalDetailViewController else { fatalError("presented view is not of type ModalDetailViewController") }
        modalDetailViewController.delegate = self
        present(modalDetailViewController, animated: true, completion: nil)
    }
    
    @objc private func pasteButtonTapped(_ sender: Any) {
        if let string = UIPasteboard.general.string {
            pasteButton.isEnabled = false
            checkAddress(for: string)
        } else {
            presentError(message: L10n.Generic.Pasteboard.invalidAddress)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    @objc private func cancelButtonTapped(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func toggleTorch() {
        scannerView.toggleTorch()
    }
}

extension QRCodeScannerViewController: ModalDetailViewControllerDelegate {
    func childWillDisappear() {
        scannerView.start()
    }
    
    func presentError(message: String) {
        Toast.presentError(message)
    }
}
