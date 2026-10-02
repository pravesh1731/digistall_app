class UserModel {
  final String userId;
  final String email;
  final String shopId;
  final String userName;
  final String userType;
  final String userStatus;
  final String profilePicture;
  final String shopType;

  UserModel({
    required this.userId,
    required this.email,
    required this.shopId,
    required this.userName,
    required this.userType,
    required this.userStatus,
    required this.profilePicture,
    required this.shopType,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    userId: json['userId'] ?? '',
    email: json['email'] ?? '',
    shopId: json['shopId'] ?? '',
    userName: json['userName'] ?? '',
    userType: json['userType'] ?? '',
    userStatus: json['userStatus'] ?? '',
    profilePicture: json['profilePicture'] ?? '',
    shopType: json['shopType'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'email': email,
    'shopId': shopId,
    'userName': userName,
    'userType': userType,
    'userStatus': userStatus,
    'profilePicture': profilePicture,
    'shopType': shopType,
  };
}
