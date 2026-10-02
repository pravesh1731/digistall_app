class ShopModel {
  final String shopId;
  final String shopName;
  final String QRCode;
  final bool cod;
  final String upiId;
  final String shopType;

  ShopModel({
    required this.shopId,
    required this.shopName,
    required this.QRCode,
    required this.cod,
    required this.upiId,
    required this.shopType,
  });

  factory ShopModel.fromJson(Map<String, dynamic> json) => ShopModel(
    shopId: json['shopId'] ?? '',
    shopName: json['shopName'] ?? '',
    QRCode: json['QRCode'] ?? '',
    cod: json['cod'] ?? false,
    upiId: json['upiId'] ?? '',
    shopType: json['shopType'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'shopId': shopId,
    'shopName': shopName,
    'QRCode': QRCode,
    'cod': cod,
    'upiId': upiId,
    'shopType': shopType,
  };
}
