import 'package:flutter/material.dart';

import 'package:navigo/controllers/app_controller_scope.dart';
import '../../localization/localization_x.dart';
import '../../services/phone_login_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import '../../widgets/responsive.dart';
import 'phone_number_screen.dart';
import '../route_manager/route_schedule.dart';

class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final PhoneLoginStorageService _storageService = PhoneLoginStorageService();

  bool _obscurePassword = true;
  bool _localLoading = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final savedEmail = await _storageService.getRememberedRouteManagerEmail();
    if (!mounted) return;

    if (savedEmail != null && savedEmail.trim().isNotEmpty) {
      _emailController.text = savedEmail;
      setState(() => _rememberMe = true);
    } else {
      setState(() => _rememberMe = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_localLoading) return;

    final auth = AppControllerScope.of(context).authController;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      AppMessage.showError(context, context.texts.t('enterEmailPassword'));
      return;
    }

    if (_rememberMe) {
      await _storageService.saveRememberedRouteManagerEmail(email);
    } else {
      await _storageService.clearRememberedRouteManagerEmail();
    }
    if (!mounted) return;

    setState(() => _localLoading = true);

    final role = await auth.signInWithEmail(email, password);

    if (!mounted) return;

    setState(() => _localLoading = false);

    if (role == 'route_manager') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RouteSchedule()),
      );
    } else {
      AppMessage.showError(
        context,
        auth.error ?? context.texts.t('loginFailed'),
      );
    }
  }

  void _goBack() {
    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    // After a route manager logs out, EmailLoginScreen is placed as the root
    // route. Popping that root route leaves a black screen, so route back to
    // the normal phone login entry point instead.
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const PhoneNumberScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _localLoading;
    final padding = Responsive.horizontalPadding(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: NavigoColors.backgroundLight,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              NavigoDecorations.topBar1(onBack: _goBack, context: context),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    // Responsive form padding prevents cramped small-phone
                    // layouts and keeps the login card balanced on tablets.
                    padding: EdgeInsets.all(padding),
                    child: ConstrainedBox(
                      constraints: Responsive.contentMaxWidth(context),
                      child: Container(
                        padding: EdgeInsets.all(padding.clamp(16, 24)),
                        decoration: NavigoDecorations.kCardDecoration,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.texts.t('routeManager'),
                              style: NavigoTextStyles.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.texts.t('routeManagerLoginSubtitle'),
                              style: NavigoTextStyles.bodyMedium,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              context.texts.t('email'),
                              style: NavigoTextStyles.label,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              enabled: !isLoading,
                              style: NavigoTextStyles.fieldText,
                              decoration: NavigoDecorations.kInputDecoration
                                  .copyWith(
                                    hintText: 'RouteManager@navigo.com',
                                    prefixIcon: const Icon(
                                      Icons.email_outlined,
                                      color: NavigoColors.accentGreen,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.texts.t('password'),
                              style: NavigoTextStyles.label,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              enabled: !isLoading,
                              onSubmitted: (_) => _signIn(),
                              style: NavigoTextStyles.fieldText,
                              decoration: NavigoDecorations.kInputDecoration
                                  .copyWith(
                                    prefixIcon: const Icon(
                                      Icons.lock_outline,
                                      color: NavigoColors.accentGreen,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: isLoading
                                          ? null
                                          : () {
                                              setState(() {
                                                _obscurePassword =
                                                    !_obscurePassword;
                                              });
                                            },
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              value: _rememberMe,
                              onChanged: isLoading
                                  ? null
                                  : (value) {
                                      setState(
                                        () => _rememberMe = value ?? false,
                                      );
                                    },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                context.texts.t('rememberMe'),
                                style: NavigoTextStyles.bodyMedium,
                              ),
                            ),
                            const SizedBox(height: 25),
                            SizedBox(
                              width: double.infinity,
                              height: Responsive.buttonHeight(context),
                              child: ElevatedButton(
                                style:
                                    NavigoDecorations.kPrimaryButtonLargeStyle,
                                onPressed: isLoading ? null : _signIn,
                                child: isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: NavigoColors.textLight,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            context.texts.t('signIn'),
                                            style: NavigoTextStyles.button,
                                          ),
                                          const SizedBox(width: 10),
                                          const Icon(Icons.arrow_forward),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: TextButton(
                                onPressed: isLoading ? null : _goBack,
                                child: Text(
                                  context.texts.t('backToUserLogin'),
                                  style: NavigoTextStyles.actionLink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
