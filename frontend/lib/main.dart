import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/wallet_setup_screen.dart';
import 'providers/wallet_provider.dart';
import 'services/storage_service.dart';
import 'database/database_init.dart';
import 'screens/send_ot_request_screen.dart';
import 'screens/send_ot_proof_screen.dart';
import 'screens/ot_cycle_list_screen.dart';
import 'screens/ot_my_requests_screen.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database factory for the platform
  await initializeDatabaseForPlatform();

  // Check if wallet exists
  final hasWallet = await StorageService.instance.isWalletInitialized();

  runApp(SPVWalletApp(hasWallet: hasWallet));
}

class SPVWalletApp extends StatelessWidget {
  final bool hasWallet;

  const SPVWalletApp({
    super.key,
    required this.hasWallet,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletProvider(),
      child: MaterialApp(
        title: 'SPV Wallet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          brightness: Brightness.light,
          scaffoldBackgroundColor: Colors.grey[50],
          cardTheme: const CardThemeData(
            color: Colors.white,
            elevation: 2,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          useMaterial3: true,
        ),
        // Force light mode - ignore system dark mode
        themeMode: ThemeMode.light,
        // Route to setup or home based on wallet existence
        home: hasWallet ? const HomeScreen() : const WalletSetupScreen(),

        routes: {
          '/ot_request': (context) => const SendOTRequestScreen(),
          '/ot_proof': (context) {
            final args = ModalRoute.of(context)!.settings.arguments
                as Map<String, dynamic>?;
            return SendOTProofScreen(
              initialRequestTxid: args?['txid'] as String?,
              initialOffsetAmountBTC: args?['amount'] as String?,
            );
          },

          '/ot_cycle_list': (context) => const OTCycleListScreen(),

          // Add missing /ot_my_requests route
          '/ot_my_requests': (context) => const OtMyRequestsScreen(),
        },
      ),
    );
  }
}
